import jester
import std/[algorithm, asyncdispatch, httpclient, locks, json, options, posix,
    sequtils, strutils, sugar, tables, times]

onSignal(SIGINT, SIGTERM):
  quit(QuitSuccess)

type
  Room = object
    name: string
    hasPassword: bool
    environment: string
    lastInteractionTime: string
    isHibernating: bool
    creator: string
    server: Option[string]
    visitors: Option[seq[string]]

  Server = object
    address: string
    maxRooms: uint16
    environments: seq[string]
    lastUpdate: DateTime

  Environment = object
    ID: string
    Name: string
    Description: Option[string]


var roomsLock, serversLock, environmentsLock: Lock
initLock(roomsLock)
initLock(serversLock)
initLock(environmentsLock)

var rooms {.guard: roomsLock.} = newSeq[Room]()
var servers {.guard: serversLock.} = newTable[string, Server]()
var environments {.guard: environmentsLock.} =
  newOrderedTable[string, Environment]()

var client = newAsyncHttpClient()

proc numRooms(server: Server): uint =
  withLock roomsLock:
    return uint(len(rooms.filter(room => room.server.get() == server.address)))

proc isFull(server: Server): bool =
  return server.numRooms >= server.maxRooms

proc deadCheck() =
  withLock serversLock:
    # Detect servers which have not updated recently
    let oldServers = servers.values().toSeq()
      .filter(server =>
        (now() - server.lastUpdate) > initDuration(seconds = 60 * 15))
      .map(server => server.address)

    for server in oldServers:
      servers.del(server)

    # Remove rooms hosted on dead server
    withLock roomsLock:
      rooms = rooms.filter(room => not (room.server.get in oldServers))

routes:
  get "/server/status":
    withLock serversLock:
      # Server statistics
      let maxRoomsSum = if len(servers) > 0:
          toSeq(servers.values()).map(server => server.maxRooms).foldl(a + b) else: 0

      withLock roomsLock:
        resp Http200, @[("Content-Type", "application/json"), (
          "Access-Control-Allow-Origin", "*")], $(%*{"activeRooms": len(
              filter(rooms, r => not r.isHibernating)),
          "hibernatingRooms": len(filter(rooms, r => r.isHibernating)),
              "maxRooms": maxRoomsSum})
  get "/environments/list":
    # List all environments
    withLock environmentsLock:
      resp Http200, @[("Content-Type", "application/json"), (
        "Access-Control-Allow-Origin", "*")], $(%*toSeq(environments.values))
  get "/rooms/list":
    deadCheck()

    withLock roomsLock:
      # List rooms
      var respRooms = rooms

      # Filter to user's rooms
      if request.params.hasKey("user"):
        respRooms = rooms.filter(
          room => room.visitors.get().contains(request.params["user"]))

      # Output only relevant fields
      resp Http200, @[("Content-Type", "application/json"), (
          "Access-Control-Allow-Origin", "*")], $(%*(respRooms.map(room => {
              "id": room.name, "server": room.server.get(),
              "environment": room.environment}.toTable)))

  get "/rooms/info":
    withLock roomsLock:
      if request.params.hasKey("id"):
        let matches = rooms.filter(room => room.name == request.params["id"])

        if len(matches) > 0:
          resp Http200, @[("Content-Type", "application/json"), (
            "Access-Control-Allow-Origin", "*")], $(%*matches[0])
          return

      resp Http404, "Room not found"

  post "/rooms/create":
    deadCheck()

    withLock serversLock:
      # Request to create a room
      var environment = "default"
      if request.params.hasKey("environment") and
        len(request.params["environment"]) > 0:
        environment = request.params["environment"]

      # Determine if valid server exists
      if len(servers.values().toSeq()
        .filter(server => environment in server.environments and
            not server.isFull())) == 0:
        echo "No servers available"
        resp Http500, "No servers available"
        return

      # Determine which server is best to use
      let sortedServers = sorted(servers.values.toSeq(),
        (a, b) => cmp(a.numRooms(), b.numRooms()))

      # Request room from server
      try:
        let targetServer = sortedServers[0]
        let reqBody = request.params.pairs().toSeq()
          .map(pair => pair[0] & "=" & pair[1]).join("&")
        let targetResponse = parseJson(await client.postContent("http://" &
            targetServer.address & ":8000/rooms/create", reqBody))
        targetResponse.add("server", %*targetServer.address)

        resp Http200, @[("Content-Type", "application/json"), (
            "Access-Control-Allow-Origin", "*")], $targetResponse
      except:
        echo "Error requesting room from " & sortedServers[0].address
        resp Http500

  post "/server/announce":
    withLock serversLock:
      # Incoming report from other server
      if request.params.hasKey("maxRooms"):
        servers[request.ip] = Server(address: request.ip,
          maxRooms: uint16(parseInt(request.params["maxRooms"])),
            lastUpdate: now())

    resp ""
  put "/server/rooms":
    withLock serversLock:
      # Incoming report from other server
      if request.ip in servers:
        if request.params.hasKey("rooms"):
          try:
            withLock roomsLock:
              var parsedRooms = to(parseJson(request.params["rooms"]), seq[Room])
              # Remove existing entries
              rooms = rooms.filter(room => room.server.get() != request.ip)

              # Add new entries
              for room in parsedRooms:
                var tempRoom = room
                tempRoom.server = some(request.ip)
                rooms.add(tempRoom)

            servers[request.ip].lastUpdate = now()

          except Exception as e:
            echo "Error reading rooms: ", e.msg
    resp ""
  delete "/server/rooms":
    withLock serversLock:
      # Incoming report from other server
      if request.ip in servers:
        if request.params.hasKey("rooms"):
          try:
            var parsedRooms = to(parseJson(request.params["rooms"]), seq[Room])

            withLock roomsLock:
              rooms = rooms.filter(room => not(room.name in parsedRooms.map(
                  room => room.name)))
          except Exception as e:
            echo "Error reading rooms: ", e.msg

          servers[request.ip].lastUpdate = now()

    resp ""
  patch "/server/rooms":
    withLock serversLock:
      # Incoming report from other server
      if request.ip in servers:
        if request.params.hasKey("rooms"):
          try:
            withLock roomsLock:
              var parsedRooms = to(parseJson(request.params["rooms"]), seq[Room])
              rooms = rooms.filter(room => not(room.name in parsedRooms.map(
                  room => room.name)))

              for room in parsedRooms:
                var tempRoom = room
                tempRoom.server = some(request.ip)
                rooms.add(tempRoom)

          except Exception as e:
            echo "Error reading rooms: ", e.msg

        servers[request.ip].lastUpdate = now()

    resp ""
  post "/server/environments":
    withLock serversLock:
      withLock environmentsLock:
        # Incoming report from other server

        if request.ip in servers:
          if request.params.hasKey("environments"):
            try:
              let inData = parseJson(request.params["environments"])
              let inSeq = to(inData, seq[Environment])

              for inEnv in inSeq:
                if not (inEnv.ID in environments):
                  environments[inEnv.ID] = inEnv
                if not (inEnv.ID in servers[request.ip].environments):
                  servers[request.ip].environments.add(inEnv.ID)
            except Exception as e:
              echo "Error reading environments: ", e.msg

            servers[request.ip].lastUpdate = now()

    resp ""

runForever()
