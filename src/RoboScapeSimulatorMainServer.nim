import jester, json, posix
import std/sequtils
import std/sugar
import std/strutils
import std/options
import std/tables

onSignal(SIGINT, SIGTERM):
  quit(QuitSuccess)

type
  Room = object
    id: string
    server: string
    environment: string
    users: seq[string]
    hibernating: bool

  Server = object
    address: string
    maxRooms: uint16
    environments: seq[string]

  Environment = object
    ID: string
    Name: string
    Description: Option[string]

var rooms = newSeq[Room]()
var servers = newTable[string, Server]()
var environments = newOrderedTable[string, Environment]()

routes:
  get "/server/status":
    # Server statistics
    let maxRoomsSum = if len(servers) > 0:
      toSeq(servers.values()).map(server => server.maxRooms).foldl(a + b) else: 0
    resp Http200, @[("Content-Type", "application/json"), (
        "Access-Control-Allow-Origin", "*")], $(%*{"activeRooms": len(filter(
            rooms, r => not r.hibernating)),
        "hibernatingRooms": len(filter(rooms, r => r.hibernating)),
            "maxRooms": maxRoomsSum})
  get "/environments/list":
    # List all environments
    resp Http200, @[("Content-Type", "application/json"), (
        "Access-Control-Allow-Origin", "*")], $(%*toSeq(environments.values))
  get "/rooms/list":
    # List rooms
    var respRooms = rooms

    # Filter to user's rooms
    if request.params.hasKey("user"):
      respRooms = rooms.filter(room => room.users.contains(request.params["user"]))

    # Output only relevant fields
    resp Http200, @[("Content-Type", "application/json"), (
        "Access-Control-Allow-Origin", "*")], $(%*(respRooms.map(room => {
            "id": room.id, "server": room.server,
            "environment": room.environment}.toTable)))

  post "/rooms/create":
    # Request to create a room
    resp Http200, @[("Content-Type", "application/json"), (
        "Access-Control-Allow-Origin", "*")], $(%*{"roomID": "", "server": ""})

  post "/server/announce":
    # Incoming report from other server
    if not (request.ip in servers):
      if request.params.hasKey("maxRooms"):
        servers[request.ip] = Server(address: request.ip,
            maxRooms: uint16(parseInt(request.params["maxRooms"])))

    resp ""
  post "/server/rooms":
    # Incoming report from other server
    if request.ip in servers:
      if request.params.hasKey("rooms"):
        echo request.params["rooms"]
    resp ""
  post "/server/environments":
    # Incoming report from other server

    if request.ip in servers:
      if request.params.hasKey("environments"):
        try:
          let inData = parseJson(request.params["environments"])
          let inSeq = to(inData, seq[Environment])

          for inEnv in inSeq:
            if not (inEnv.ID in environments):
              environments[inEnv.ID] = inEnv
        except:
          echo "Error parsing environments"
    resp ""
