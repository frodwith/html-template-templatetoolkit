use HTML::Template::TemplateToolkit;

print HTML::Template::TemplateToolkit->translate(do { local $/; <> });
