package WebGUI::Asset::Wobject::HT_TT;

use HTML::Template::TemplateToolkit;
use Try::Tiny;

use warnings;
use strict;

use base 'WebGUI::Asset::Wobject';

sub getName { 'HT->TT Converter' }

sub view {
    my $self    = shift;
    my $session = $self->session;
    my $url     = $session->url;
    my $style   = $session->style;
    my $action  = $self->getUrl;
    for my $y (qw(yahoo/yahoo-min.js
                  event/event-min.js
                  connection/connection-min.js))
    {
        $style->setScript($url->extras("yui/build/$y"));
    }
    $style->setScript($url->extras('yui/build/connection/connection-min.js'));
    $style->setRawHeadTags(<<STYLE);
<style>
.codebox { width: 100%; height: 24em; font-family: monospace }
</style>
STYLE
    my $controls = $session->var->isAdminOn && $self->getToolbar || '';
return <<"RAW_HTML";
<div>
$controls
<p>Paste your template here and click this button:<button
id='template_convert'>Convert</button></p>
<textarea class='codebox' id='template_input'></textarea>
<p>And your converted template will appear here:</p>
<textarea class='codebox' id='template_output'></textarea>
<script>
(function () {
    var input   = document.getElementById('template_input'),
    output      = document.getElementById('template_output'),
    btn         = document.getElementById('template_convert');
    btn.onclick = function () {
        YAHOO.util.Connect.asyncRequest('POST', '$action', {
            success: function (r) {
                output.value = r.responseText;
            }
        }, 'func=translate&template=' + escape(input.value));
    };
}());
</script>
</div>
RAW_HTML
}

sub www_translate {
    my $self = shift;
    my $session = $self->session;
    $session->http->setMimeType('text/plain');
    try {
        HTML::Template::TemplateToolkit->translate($session->form->get('template'));
    }
    catch {
        $_;
    };
}

1;
