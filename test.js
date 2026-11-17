const { build } = require('./test/helpers')

build('test/fixtures/addon')
build('test/fixtures/install-off', { install: false })
build('test/fixtures/runtime-dependency')
