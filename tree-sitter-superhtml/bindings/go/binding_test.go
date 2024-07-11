package tree_sitter_html_test

import (
	"testing"

	tree_sitter "github.com/smacker/go-tree-sitter"
	"github.com/tree-sitter/tree-sitter-html"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_html.Language())
	if language == nil {
		t.Errorf("Error loading HTML grammar")
	}
}
