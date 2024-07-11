(erroneous_end_tag_name) @tag.error
(doctype) @constant
(comment) @comment

((tag_name) @special
  (#any-of? @special "super" "extend"))
(tag_name) @tag

; (
;   (element
;     (start_tag
;       (tag_name) @special))
;   (element
;     (start_tag
;       (attribute
;         (attribute_name) @attribute
;         [
;           (attribute_value) @markup.link.url
;           (quoted_attribute_value (attribute_value) @markup.link.url)
;         ])))
;   (#eq? @special "extend")
;   (#eq? @attribute "id")
; )


(
  (element
    (start_tag
      (attribute 
        (attribute_name) @attribute
        [
          (attribute_value) @markup.link.url
          (quoted_attribute_value (attribute_value) @markup.link.url)
        ]))
    (element
      (start_tag
        (tag_name) @tag)))
  (#eq? @tag "super")
  (#eq? @attribute "id")
)

(
  (element
    (start_tag
      (tag_name) @special
      (attribute
        (attribute_name) @error)+))
  (#eq? @special "super")
)

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
