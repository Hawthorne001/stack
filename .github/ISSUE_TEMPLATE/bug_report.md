---
name: Bug Report
about: Report a bug in Stack
---

Please follow the steps below for reporting a bug in Stack:

Make sure that you are using the latest release (currently Stack 3.7.1). See the
[upgrade instructions](http://docs.haskellstack.org/en/stable/install_and_upgrade/#upgrade)
to upgrade.

Please use the following schema for your bug report:

### General summary/comments (optional)

### Steps to reproduce

For example:

1. Remove directory *blah*.
2. Run command `stack blah`.
3. Edit file *blah*.
4. Run command `stack blah`.

Include any `.yaml` configuration, if relevant.

### Expected

What you expected to see and happen.

### Actual

What actually happened.

If you suspect that a Stack command misbehaved, please include the output of
that command in `--verbose` mode. If the output is larger than a page please
paste the output in a [Gist](https://gist.github.com/).

~~~text
stack <your command here> <args> --verbose
<output>
~~~

### Stack version

~~~text
stack --version
Version 3.7.1, Git revision cfae313a06ea9f7278e0ac55a58341fa0440f1aa x86_64 hpack-0.38.1
~~~

### Method of installation

* Official binary, downloaded via haskellstack.org or from Stack's repository
* Via GHCup
* Via Cabal (the tool)
* An unofficial package repository (please specify which)
* Other (please specify)

### Platform

Your platform (machine architecture and operating system)
