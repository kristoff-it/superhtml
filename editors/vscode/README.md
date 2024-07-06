# SuperHTML LSP VSCode Extension

This extension gives you reasonable diagnostics and autoformatting on HTML files.

![](./vscode-autoformat.mp4)

**NOTE: you will need to get the `super` CLI tool and have it available in your PATH!**

For prebuilt binaries and more info: https://github.com/kristoff-it/super-html


## Diagnostics

![](./vscode.png)

This language server is stricter than the HTML spec whenever it would prevent potential human errors from being reported.


As an example, HTML allows for closing some tags implicitly. For example the following snipped is correct HTML.

```html
<ul>
  <li> One
  <li> Two
</ul>
```

This will still be reported as an error by SuperHTML because otherwise the following snippet would have to be considered correct (while it's much probably a typo):

```html
<h1>Title<h1>
```

## Autoformatting

The autoformatter has two main ways of interacting with it in order to request for horizontal / vertical alignment.

1. Adding / removing whitespace between the **start tag** of an element and its content.
2. Adding / removing whitespace between the **last attribute** of a start tag and the closing  `>`.


### Example of rule #1
Before:
```html
<div> <p>Foo</p></div>
```

After:
```html
<div> 
    <p>Foo</p>
</div>
```

#### Reverse

Before:
```html
<div><p>Foo</p>
</div>
```

After:
```html
<div><p>Foo</p></div>
```

### Example of rule #2
Before:
```html
<div foo="bar" style="verylongstring" >
    Foo
</div>
```

After:
```html
<div 
   foo="bar" 
   style="verylongstring" 
>
    Foo
</div>
```

#### Reverse

Before:
```html
<div 
   foo="bar" 
   style="verylongstring">
    Foo
</div>
```

After:
```html
<div foo="bar" style="verylongstring">
    Foo
</div>
```

