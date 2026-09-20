# flymake-biomejs

Flymake backend for linting with [Biome](https://biomejs.dev/), the
"toolchain of the web".

Unlike <https://github.com/erickgnavar/flymake-biome>, this backend uses the
"experimental" JSON reporter, and has a different method of initialising to
cope with the matrix of JavaScript package managers and projects which may or
may not use Biome. Care has been taken to minimise the latency of parsing and
reporting diagnostics.

## Usage

This package is set up such that the function `flymake-biomejs-turn-on` may be
globally added to the major mode's hook, and only run `flymake-biomejs` in
projects which have been set up to use Biome.

For example, to set up globally and then lint files in a project that uses NPM,
add something like this to your init file:

```lisp
(use-package flymake-biomejs
  :hook (typescript-ts-mode . flymake-biomejs-turn-on))
```

Then in your project, set the correct variables in `.dir-locals.el` or `.dir-locals-2.el`:

```lisp
;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((typescript-ts-mode . ((flymake-biomejs-program "npx" "biome")
                        (flymake-biomejs-enabled . t))))
```

## Why not LSP?

- Eglot only supports one LSP connection at a time without a multiplexer
  (<https://github.com/joaotavora/rassumfrassum>). Flymake supports multiple
  sources, one of which can be Eglot's, so using Biome with tsserver, for
  example, requires less ceremony.
- LSPs are long running processes which require lifecycle management. In Emacs
  we have had asynchronous subprocesses since forever and it's easier to reason
  about one that runs in one shot.
- You may wish to run the linter without an LSP connection anyway.
- Just because LSP relieves us of the task of writing an Emacs integration for
  this and that tool, doesn't mean that it isn't worth doing sometimes.

## AI Declaration

Claude Fable 5.1 was used to discuss approaches, find bugs and measure
performance during development, but was *not* permitted to generate code. I
affirm that all Lisp in <flymake-biomejs.el> was entered by hand. I'm in no
position to say whether this makes the code 'generated', strictly speaking, or a
derived work of the training data of the model.

## Licence

Copyright (C) 2026 Lina Bhaile <emacs-devel@linabee.uk>

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <https://www.gnu.org/licenses/>.
