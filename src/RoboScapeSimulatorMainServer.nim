import jester, json, posix
import std/sequtils
import std/sugar
import std/strutils

onSignal(SIGINT, SIGTERM):
  quit(QuitSuccess)

type
  Room = object
    id: string
    server: string
    environment: string
    users: seq[string]
    hibernating: bool

type
  Server = object
    address: string
    maxRooms: uint16
    environments: seq[string]

type
  Environment = object
    id: string
    name: string
    description: string

var rooms = newSeq[Room]()
var servers = newTable[string, Server]()
var environments = newSeq[Environment]()

routes:
  get "/server/status":
    # Server statistics
    let maxRoomsSum = if len(servers) > 0:
      toSeq(servers.values()).map(server => server.maxRooms).foldl(a + b) else: 0
    resp %*{"activeRooms": len(filter(rooms, r => not r.hibernating)),
        "hibernatingRooms": len(filter(rooms, r => r.hibernating)),
            "maxRooms": maxRoomsSum}
  get "/environments/list":
    # List all environments
    resp %*environments
  get "/rooms/list":
    # List rooms
    var respRooms = rooms

    # Filter to user's rooms
    if request.params.hasKey("user"):
      respRooms = rooms.filter(room => room.users.contains(request.params["user"]))

    # Output only relevant fields
    resp %*(respRooms.map(room =>
        {"id": room.id, "server": room.server,
            "environment": room.environment}.toTable))
  post "/rooms/create":
    # Request to create a room
    resp %*{"roomID": "", "server": ""}
  post "/server/announce":
    # Incoming report from other server
    echo request.params
    echo request.formData
    echo request.body
    echo request.ip

    if not (request.ip in servers):
      servers[request.ip] = Server(address: request.ip,
          maxRooms: uint16(parseInt(request.params["maxRooms"])))

    resp ""
  post "/server/rooms":
    # Incoming report from other server
    echo request.params
    echo request.formData
    echo request.body
    resp ""
  post "/server/environments":
    # Incoming report from other server
    echo request.params
    echo request.formData
    echo request.body
    resp ""
