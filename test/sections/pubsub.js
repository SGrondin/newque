var fs = require('fs')
var protobuf = require("protocol-buffers")
var specs = protobuf(fs.readFileSync('../protobuf/zmq_obj.proto'))
var zmq = require('zmq')
var socket1 = zmq.socket('sub')
var socket2 = zmq.socket('sub')

module.exports = function (backend, backendSettings, raw) {
  var delay = backend === 'elasticsearch' ? C.esDelay : 0
  describe('Pubsub' + (!!raw ? ' raw' : ''), function () {
    var processes = []
    var pubsubPorts
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(backend, backendSettings, raw)
      .then(function (env) {
        env.processes.forEach((p) => processes.push(p))
        pubsubPorts = env.pubsubPorts
        return Promise.delay(C.spawnDelay)
      })
    })

    it('Pull', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldFail(400))
    })

    it('Count', function () {
      return Fn.call('GET', 8000, '/v1/example/count')
      .then(Fn.shouldFail(500))
    })

    it('Push to multiple subscribers', function () {
      var originalIds = ['id1', 'id2', 'id3', 'id4']
      var originalIdsStr = originalIds.join(',')
      var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`

      var receiveOnSocket = function (socket) {
        return new Promise(function (resolve, reject) {
          var addr = 'tcp://127.0.0.1:' + pubsubPorts.example
          socket.connect(addr)
          socket.subscribe(new Buffer([]))
          socket.on('message', function (input, msg1, msg2, msg3, msg4) {
            var decoded = specs.Input.decode(input)
            Fn.assert(decoded.channel.toString('utf8') === 'example')
            Fn.assert(decoded.write_input.atomic !== true)
            var receivedIds = decoded.write_input.ids.map(x => x.toString('utf8'))
            Fn.assert(receivedIds.join(',') === originalIdsStr)
            var splitBuf = buf.split('\n')

            Fn.assert(msg1.toString('utf8') === splitBuf[0])
            Fn.assert(msg2.toString('utf8') === splitBuf[1])
            Fn.assert(msg3.toString('utf8') === splitBuf[2])
            Fn.assert(msg4.toString('utf8') === splitBuf[3])

            socket.removeAllListeners('message')
            socket.disconnect(addr)
            resolve()
          })
        })
      }
      var receive1 = receiveOnSocket(socket1)
      var receive2 = receiveOnSocket(socket2)
      return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, originalIdsStr]])
      .then(Fn.shouldHaveWritten(4))
      .then(() => receive1)
      .then(() => receive2)
    })

    it('Delete', function () {
      Fn.call('DELETE', 8000, '/v1/example')
      .then(Fn.shouldFail(400))
    })

    after(function () {
      return Proc.teardown(processes, backend, backendSettings)
    })
  })
}