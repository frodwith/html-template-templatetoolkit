package HTML::Template::TemplateToolkit;
use Parse::RecDescent;

use warnings;
use strict;

my $grammar = <<'GRAMMAR';
    template     : <skip:''> part(s?) 
    part         : tag | /.[^<]*/s

    qq_default       : /[^">]*/
    q_default        : /[^'>]*/
    unquoted_default : /[^'"\s=>]*/

    default_val  : '"' qq_default '"' { $item{qq_default} }
                 | "'" q_default "'"  { $item{q_default}  }
                 | unquoted_default

    default_attr : /default\s*=\s*/i default_val { {default => $item[-1]} }

    bare_name    : /[a-zA-Z0-9.\/+\-_]+/ 

    name         : bare_name 
                 | '"' bare_name '"' { $item{bare_name} }
                 | "'" bare_name "'" { $item{bare_name} }

    name_prefix  : /name\s*=\s*/i
    name_attr    : name_prefix(?) name { {name => $item[-1] } }

    esc_type     : /url/i | /html/i | /js/i | /true/i | /none/i | '1' | '0'
    esc          : esc_type
                 | '"' esc_type '"' { $item{esc_type} }
                 | "'" esc_type "'" { $item{esc_type} }
    esc_attr     : /escape\s*=\s*/i esc { { escape => $item[-1] } }


    end_default  : /\s+/ default_attr
    st_default   : default_attr /\s+/ { $item[1] }

    end_esc      : /\s+/ esc_attr
    st_esc       : esc_attr /\s+/ { $item[1] }

    mid_attrs    : st_default st_esc(s?) name_attr     { [@item] }
                 | name_attr st_esc(s?) end_default(?) { [@item] }

    var_attrs    : st_esc(s?) mid_attrs end_esc(s?)    { [@item] }

    tmpl_var     : tag_open /tmpl_var\s+/i var_attrs tag_close
        { 
            my $var = { tag => 'var' };
            my $search;
            $search = sub {
                my $arr = shift;
                for my $thing (@$arr) {
                    if (ref $thing eq 'ARRAY') {
                        $search->($thing);
                    }
                    elsif(ref $thing eq 'HASH') {
                        if (my $n = $thing->{name}) {
                            $var->{name} = $n;
                        }
                        elsif (my $d = $thing->{default}) {
                            $var->{default} = $d;
                        }
                        elsif (my $e = $thing->{escape}) {
                            push(@{$var->{escapes}}, $e);
                        }
                    }
                }
            };
            $search->($item{var_attrs});
            undef $search;
            $var;
        }


    tmpl_if      : tag_open /tmpl_if\s+/i     name_attr tag_close
        { {tag => 'if', name => $item{name_attr}->{name}} }

    tmpl_unless  : tag_open /tmpl_unless\s+/i name_attr tag_close
        { {tag => 'unless', name => $item{name_attr}->{name}} }

    tmpl_loop    : tag_open /tmpl_loop\s+/i   name_attr tag_close
        { {tag => 'loop', name => $item{name_attr}->{name}} }

    tmpl_else    : tag_open /tmpl_else/i              tag_close
        { {tag => 'else'} }

    extra_close  : /[^->]*/

    close_if     : tag_open /\/tmpl_if/i     extra_close tag_close
        { {close => 'if'} }

    close_unless : tag_open /\/tmpl_unless/i extra_close tag_close
        { {close => 'unless'} }

    close_loop   : tag_open /\/tmpl_loop/i   extra_close tag_close
        { {close => 'loop'} }

    tag          : tmpl_if  | tmpl_loop  | tmpl_unless | tmpl_var | tmpl_else
                 | close_if | close_loop | close_unless

    tag_open     : /<!--\s+/ | '<'

    tag_close    : /\s*-->/ | /\s*>/
GRAMMAR

my $parser = Parse::RecDescent->new($grammar) or die 'Bad grammar';

sub translate {
    my $input = pop;
    my $soup  = $parser->template($input) or die 'Did not parse';
    my $root  = treeify($soup);
    return process_body($root);
}

sub treeify {
    # Build a tree out of the soup (nest ifs, loops, etc) and check for
    # balanced tags.  When we're done, we just have vars, ifs/unlesses, and
    # loops.  All the closing tags have been acted upon, elses have become
    # part of their conditionals.
    my $soup  = shift;
    my @stack = ([]);
    foreach my $element (@$soup) {
        my $top = $stack[-1];
        push(@$top, $element);

        if (ref $element) {
            if (my $t = $element->{tag}) {
                if ($t eq 'if' || $t eq 'loop' || $t eq 'unless') {
                    push(@stack, $element->{body} = []);
                }
                if ($t eq 'else') {
                    pop(@$top);
                    my $parent = $stack[-2] or die "else with no enclosing tag";
                    $parent = $parent->[-1];
                    my $tp = $parent->{tag};
                    if ($tp ne 'if' && $tp ne 'else') {
                        die "else with $tp parent";
                    }
                    $stack[-1] = $parent->{else} = [];
                }
            }
            elsif (my $c = $element->{close}) {
                pop(@$top);
                pop(@stack);
                $top = $stack[-1] or die "tried to close $c with nothing open";
                if ((my $t = $top->[-1]->{tag}) ne $c) {
                    die "Tried to close $c with $t open";
                }
            }
        }
    }
    my $root = pop(@stack);
    die "Unclosed tag somewhere" if @stack;
    return $root;
}

sub process_body {
    my $root = shift;
    my $output = '';
    foreach my $item (@$root) {
        unless (ref $item) {
            $output .= $item;
            next;
        }
        my $t = $item->{tag};
        my $name = $item->{name};
        my $lc   = lc $name;

        if ($lc eq '__first__') {
            $name = 'loop.first';
        }
        elsif ($lc eq '__last__') {
            $name = 'loop.last';
        }
        elsif ($lc eq '__even__') {
            $name = '(loop.index % 2 == 0)';
        }
        elsif ($lc eq '__odd__') {
            $name = '(loop.index % 2)';
        }
        else {
            $name =~ s/\./_/g;
        }

        if ($t eq 'if' || $t eq 'unless') {
            my $tag = $t eq 'if' ? 'IF' : 'UNLESS';
            $output .= "[% $tag $name %]";
            $output .= process_body($item->{body});
            if (my $else = $item->{else}) {
                $output .= '[% ELSE %]' . process_body($else);
            }
            $output .= '[% END %]'
        }
        elsif ($t eq 'loop') {
            $output .= "[% FOREACH item IN $name; FOREACH [item] %]";
            $output .= process_body($item->{body});
            $output .= '[% END;END %]';
        }
        elsif ($t eq 'var') {
            my %escape;
            foreach my $e (map { lc } @{$item->{escapes}}) {
                if ($e eq '1' || $e eq 'html' || $e eq 'true') {
                    $escape{html} = 1;
                }
                elsif ($e eq 'js') {
                    $escape{js} = 1;
                }
                elsif ($e eq 'url') {
                    $escape{url} = 1;
                }
            }
            if ($escape{js}) {
                $name = "($name"
                    . q|.replace('\\\\', '\\\\\\\\')|
                    . q|.replace("'", "\\\\'")|
                    . q|.replace('"', '\\\\"')|
                    . q|.replace('\\n', '\\\\n')|
                    . q|.replace('\\r', '\\\\r')|
                    . ')';
            }
            if ($escape{html}) {
                $name = "($name | html)";
            }
            if ($escape{url}) {
                $name = "($name | uri)";
            }
            my $default = '';
            $output .= "[% $name ";
            if (my $d = $item->{default}) {
                $d =~ s/'/\\'/g;
                $output .= "|| '$d' ";
            } 
            $output .= '%]';
        }
        else {
            die "Unknown tag $t";
        }
    }
    return $output;
}

1;
