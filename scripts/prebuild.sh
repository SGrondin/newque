#! /bin/bash

rm -rf tmp
mkdir tmp
cp libnewque_stubs.clib tmp/

# Remove old generated ATD parsers
rm -f src/config/config_*.ml*
rm -f src/serialization/json_obj_*.ml*

# Format the source files
find src -type f -name "*.ml*" | xargs ocp-indent --config align_ops=false,strict_else=auto -i

# Generate new ATD parsers
atdgen -t ./src/config/config.atd
atdgen -j -j-std ./src/config/config.atd
atdgen -t ./src/serialization/json_obj.atd
atdgen -j -j-std ./src/serialization/json_obj.atd

# Copy the protobuf specs to the top level protobuf/ directory
cp src/serialization/zmq_obj.proto specs/zmq_api.proto

# Generate protobuf parsers
ocaml-protoc -ml_out src/serialization src/serialization/zmq_obj.proto

# Run the preprocessor on .ml and .mli, and copy the output to tmp/
find src -type f -name '*.ml*' -print0 | xargs -0 -I % sh -c 'cppo -I src/persistence/redis/scripts -D DEBUG -n % -o tmp/`basename %`'
# Copy C files to tmp/
find src -type f -name '*.c' -print0 | xargs -0 -I % sh -c 'cp % tmp/`basename %`'
find src -type f -name '*.h' -print0 | xargs -0 -I % sh -c 'cp % tmp/`basename %`'
