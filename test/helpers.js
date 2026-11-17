const test = require('brittle')
const fs = require('fs')
const path = require('path')
const make = require('bare-make')

const modules = path.resolve(__dirname, '..', 'node_modules')

exports.build = function build(fixture, opts = {}) {
  const { install = true } = opts

  test(fixture, { timeout: 300000 }, async (t) => {
    const cwd = path.resolve(__dirname, '..', fixture)

    await make.generate({
      cwd,
      source: '.',
      build: 'build',
      cache: false,
      define: [`CMAKE_PREFIX_PATH=${modules}`],
      stdio: 'inherit'
    })

    await make.build({ cwd, build: 'build', clean: true, stdio: 'inherit' })

    await make.install({ cwd, build: 'build', prefix: 'prebuilds', stdio: 'inherit' })

    if (!install) {
      t.absent(fs.existsSync(path.join(cwd, 'prebuilds')), 'installs nothing')
      return
    }

    t.is(require(prebuild(cwd)), 42, 'loads')
  })
}

function prebuild(cwd) {
  const prebuilds = path.join(cwd, 'prebuilds')

  for (const target of fs.readdirSync(prebuilds)) {
    for (const file of fs.readdirSync(path.join(prebuilds, target))) {
      if (file.endsWith('.node')) return path.join(prebuilds, target, file)
    }
  }

  throw new Error(`No prebuild found in ${prebuilds}`)
}
