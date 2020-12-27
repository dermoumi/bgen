# bgen - a script generator for bash

bgen is a simple utility that allows you to generate a single bash script from multiple files.

## Table of contents

- [Usage](#usage)
  - [The meta.sh file](#the-metash-file)
- [Directives](#directives)
  - [bgen:import](#bgenimport)
  - [bgen:include_str](#bgeninclude_str)

## Usage

Put [`bgen`](./bin/bgen) in the same folder as a [`meta.sh`[(#the-metash-file)] file in your project and run:

```bash
# Output the generated file to stdout
./bgen

# run the project
./bgen run [ARGS..]

# build the project
./bgen build
```

### The meta.sh file

`meta.sh` is a file that contains configuration for __bgen__, all settings are optional.

```bash
# name of the project
# defaults to the name of the directory of meta.sh
bgen_project_name=

# file to include before everything
# if left empty, bgen includes its default header file
bgen_header_file=

# main entrypoint file of the script
# if left empty, bgen uses src/main.sh relative to meta.sh
bgen_entrypoint_file=

# name of the main function of the project
# if left empty, bgen does not call any main function
bgen_entrypoint_func=

# string to use as a shebang for the output file
# if left empty, bgen uses `#!/bin/bash`
bgen_shebang_string=

# file to output the generated project to
# if left empty, bgen uses 'bin/<project_name>' relative to meta.sh
bgen_output_file=
```

## Directives

bgen introduces a handful of directives to help with code splitting:

### bgen:import

Imports a script file into the current file

```bash
# main.sh:

# import hello.sh
bgen:import hello

# only imports each file once accross the project, so avoid putting it inside local scopes
bgen:import hello # will not be imported again

# will attempt to import `file.other_ext.sh` first then `file.other_ext`
# aborts if file does not exist
bgen:import file.other_ext

greet "world"

# hello.sh:
greet() {
    echo "Hello, $1!"
}

```

### bgen:include_str

Sets a file's content to a variable

```bash
local file_content
bgen:include_str file_content filename.txt

echo "$file_content"
```
