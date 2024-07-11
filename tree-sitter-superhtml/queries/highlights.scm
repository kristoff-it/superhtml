(erroneous_end_tag_name) @tag.error
(doctype) @constant
(comment) @comment

((tag_name) @special
  (#any-of? @special "super" "extend"))
(tag_name) @tag

; ((attribute_name) @keyword.control.conditional
;   (#match? @keyword.control.conditional "^[$]"))
(attribute_name) @attribute

[
  "\""
  (attribute_value)
] @string

[
  "<"
  ">"
  "</"
  "/>"
  "<!"
] @punctuation.bracket

"=" @punctuation.delimiter
