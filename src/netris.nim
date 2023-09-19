import random
import sdl2
import std/sequtils
import std/sugar
import std/sets
import std/algorithm

const
  WindowWidth = 640
  WindowHeight = 480
  #WindowWidth = 1920
  #WindowHeight = 1080
  FPS: float = 60.0
  Frame = 0.020

  GridWinScale = 0.9
  TileInnerPad = cint(3.0 * GridWinScale * 0.0)

  GridWidthN = 10
  GridHeightN = 20

  TileWidth = cint(min(cint(WindowHeight * GridWinScale) / GridHeightN,
    cint(WindowWidth * GridWinScale) / GridWidthN))
  TileHeight = TileWidth

  GridWidth = cint((TileWidth + TileInnerPad) * GridWidthN)
  GridHeight = cint((TileHeight + TileInnerPad) * GridHeightN)

  GridLeftPad = cint((WindowWidth - GridWidth) / 2)
  GridTopPad = cint((WindowHeight - GridHeight) / 2)

  GridX = GridLeftPad
  GridY = GridTopPad


type
  x = int
  y = int
  RP = RendererPtr

  Input {.pure.} = enum
    Left, Right, Soft, Hard, Rtr, Rtl

  Rotation {.pure.} = enum
    Zero,
    Ninety,
    OneEighty,
    TwoSeventy,

  Tetromino {.pure.} = enum
    I, T, O, L, J, S, Z

  PieceInfo = (array[4, int], array[4, int], uint32)

  Piece = ref object
    pos: (x, y)
    rotation: Rotation = Rotation.Zero
    kind: Tetromino

  Block = ref object
    color: uint32
    filled: bool

  Player = ref object
    arr: uint16 = 133
    das: uint16 = 10
    softDropSpeed: uint16 = 20
    arrTime: float32
    dasTime: float32
    softDropTime: float32
    firstMove: bool = true
    firstSoft: bool = true
    firstHard: bool = true
    firstRotation: bool = true

  WorkingPiece = ref object
    currentPiece: Piece
    bag: array[0..6, Tetromino]
    dt: float32 = 0
    speed: float32 = 200
    bagI: uint32 = 0

  Game = ref object
    workingPiece: WorkingPiece
    player: Player
    board: array[GridHeightN, array[GridWidthN, Block]]
    inputs: array[Input, bool]

func info(piece: Piece): PieceInfo
func rtl(rotation: Rotation): Rotation
func rtr(rotation: Rotation): Rotation

proc genBag(): array[0..6, Tetromino] =
  var bag = [Tetromino.I,
    Tetromino.T,
    Tetromino.O,
    Tetromino.L,
    Tetromino.J,
    Tetromino.S,
    Tetromino.Z]
  shuffle(bag)
  bag

func piece(kind: Tetromino, rotation: Rotation = Zero, pos: (x, y) = (x: 4, y: 0)): Piece =
  Piece(kind: kind, rotation: rotation, pos: pos)

proc initGame(): Game =
  let bag = genBag()
  var
    workingPiece = new WorkingPiece
    player = new Player

  workingPiece.bag = bag
  workingPiece.currentPiece = piece(bag[0])

  Game(workingPiece: workingPiece, player: player)

func incrBag(bagI: uint32): uint32 = (bagI + 1) mod 7

proc nextPiece(game: Game) =
  game.workingPiece.bagI = game.workingPiece.bagI.incrBag()
  if game.workingPiece.bagI == 0:
    game.workingPiece.bag = genBag()
    game.workingPiece.currentPiece = piece(game.workingPiece.bag[0])
  else:
    game.workingPiece.currentPiece = piece(game.workingPiece.bag[game.workingPiece.bagI])

func getR(color: uint32): uint8 =
  uint8 (color and 0xFF0000).shr 16

func getG(color: uint32): uint8 =
  uint8 (color and 0x00FF00).shr 8

func getB(color: uint32): uint8 =
  uint8 (color and 0x0000FF)

func globalToBoardCoord(pos: (int, int)): (int, int) =
  let (x, y) = pos
  assert x >= GridX and x <= GridX + GridWidth and
                        y <= GridY + GridHeight
  let
    transX = ((x - GridX).int() / TileWidth.int()).int()
    transY = ((y - GridY).int() / TileHeight.int()).int()
  (transX, transY)

func globalToBoardCoord(x: int): int =
  ((x - GridX).int() / TileWidth.int()).int()

func globalToBoardCoord(y: int): int =
  ((y - GridY).int() / TileHeight.int()).int()

func gridToGlobalCoord(pos: (int, int)): (int, int) =
  let (x, y) = pos
  assert x >= 0 and x <= GridWidthN and
                    y <= GridHeightN

  let
    transX = ((x * TileWidth) + GridX.int()).int()
    transY = ((y * TileHeight) + GridY.int()).int()
  (transX, transY)

func gridToGlobalCoord(x: int): int =
  ((x * TileWidth) + GridX.int()).int()

func gridToGlobalCoord(y: int): int =
  ((y * TileHeight) + GridY.int()).int()

proc drawRect(renderer: RP, x, y: cint; width = TileWidth, height: cint = TileHeight) =
  var rect = rect(x, y, width, height)
  renderer.drawRect(rect)

proc fillRect(renderer: RP, x, y: cint; width = TileWidth, height: cint = TileHeight) =
  var rect = rect(x, y, width, height)
  renderer.fillRect(rect)

proc setDrawColor(renderer: RP, color: uint32, alpha: uint8 = 255) =
  let
    r = color.getR()
    g = color.getG()
    b = color.getB()

  renderer.setDrawColor r, g, b, alpha

proc drawGrid(renderer: RP, game: Game) =
  for x in 0..<GridWidthN:
    for y in 0..<GridHeightN:
      renderer.setDrawColor 90, 90, 90, 255
      renderer.drawRect(
        cint(gridToGlobalCoord(x = x)),
        cint(gridToGlobalCoord(y = y)))
      if game.board[y][x] != nil and game.board[y][x].filled:
        renderer.setDrawColor game.board[y][x].color
        renderer.fillRect(
          cint(gridToGlobalCoord(x = x)),
          cint(gridToGlobalCoord(y = y)))

proc drawTetromino(renderer: RP, xs: array[4, int], ys: array[4, int], color: uint32) =
  renderer.setDrawColor color
  for (x, y) in xs.zip(ys):
    renderer.fillRect(
      x = gridToGlobalCoord(x = x).cint(),
      y = gridToGlobalCoord(y = y).cint(),
      width = TileWidth.cint(),
      height = TileHeight.cint())

proc clearLine(game: Game, ys: array[4, int]) =
  var seqY: seq[int]
  for y in ys:
    var completeLine = true
    for x in 0..<GridWidthN:
      if game.board[y][x].isNil: completeLine = false
      elif not game.board[y][x].filled: completeLine = false
    if completeLine: seqY.add(y)

  seqy = seqY.deduplicate()
  seqY.sort()

  for y in seqY:
    for row in countdown(y, 1):
      for col in 0..<GridWidthN:
        game.board[row][col] = game.board[row - 1][col]

proc setPiece(game: Game, pieceInfo: PieceInfo) =
  let (xs, ys, _) = pieceInfo
  for (x, y) in xs.zip(ys):
    var b = game.board[y][x]
    if b.isNil: new(b)
    b.color = pieceInfo[2]
    b.filled = true
    game.board[y][x] = b
  clearLine(game, ys)

func infoL(): PieceInfo =
  let
    xs = [0, 0 - 1, 0 + 1, 0 + 1]
    ys = [0, 0    , 0 - 1, 0]
    color = 0xFC8930.uint32()

  (xs, ys, color)

func infoJ(): PieceInfo =
  let
    xs = [0, 0 - 1, 0 - 1, 0 + 1]
    ys = [0, 0    , 0 - 1, 0]
    color = 0x1455DA.uint32()

  (xs, ys, color)

func infoI(): PieceInfo =
  let
    xs = [0, 0 - 1, 0 + 1, 0 + 2]
    ys = [0, 0    , 0    , 0]
    color = 0x14AAC8.uint32()

  (xs, ys, color)

func infoO(): PieceInfo =
  let
    xs = [0, 0 + 1, 0    , 0 + 1]
    ys = [0, 0    , 0 + 1, 0 + 1]
    color = 0xFDFD30.uint32()

  (xs, ys, color)

func infoS(): PieceInfo =
  let
    xs = [0, 0 - 1, 0    , 0 + 1]
    ys = [0, 0    , 0 - 1, 0 - 1]
    color = 0x40CC30.uint32()

  (xs, ys, color)

func infoT(): PieceInfo =
  let
    xs = [0, 0 - 1, 0 + 1, 0    ]
    ys = [0, 0    , 0    , 0 - 1]
    color = 0xC110CC.uint32()

  (xs, ys, color)

func infoZ(): PieceInfo =
  let
    xs = [0, 0    , 0 - 1, 0 + 1]
    ys = [0, 0 - 1, 0 - 1, 0    ]
    color = 0xBB0010.uint32()

  (xs, ys, color)

func rotateI(pieceInfo: var PieceInfo, rotation: Rotation): PieceInfo =
  case rotation
  of Zero: discard
  of Ninety:
    pieceInfo[0] = [1, 1, 1, 1]
    pieceInfo[1] = [2, 1, 0 , -1]
  of TwoSeventy:
    pieceInfo[0] = [-1, -1, -1, -1]
    pieceInfo[1] = [2, 1, 0 , -1]
  of OneEighty:
    pieceInfo[0] = [0, -1, 1, 2]
    pieceInfo[1] = [-1, -1, -1 , -1]
  pieceInfo

func rotateInfo(pieceInfo: var PieceInfo, rotation: Rotation, kind: Tetromino): PieceInfo =
  let
    (xs, ys, _) = pieceInfo

  case kind
  of Tetromino.O: discard
  of Tetromino.I: return pieceInfo.rotateI(rotation)
  else:
    for i in 0..<4:
      case rotation
      of Zero: discard
      of Ninety:
        pieceInfo[0][i] = ys[i]
        pieceInfo[1][i] = -xs[i]
      of TwoSeventy:
        pieceInfo[0][i] = -ys[i]
        pieceInfo[1][i] = xs[i]
      of OneEighty:
        pieceInfo[0][i] = -xs[i]
        pieceInfo[1][i] = -ys[i]
  pieceInfo

func moveBound(x, y: int; board: array[GridHeightN, array[GridWidthN, Block]]): bool =
  if x < 0 or x >= GridWidthN or y >= GridHeightN: return true
  if y < 0: return false
  elif board[y][x].isNil: return false
  elif board[y][x].filled: return true

func canRtl(piece: Piece, game: Game): bool =
  let
    rotated = Piece(
      pos: piece.pos,
      rotation: piece.rotation.rtl(),
      kind: piece.kind)
    (xs, ys, _) = rotated.info()

  for (x, y) in xs.zip(ys):
    if moveBound(x, y, game.board): return false
  true

func canRtr(piece: Piece, game: Game): bool =
  let
    rotated = Piece(
      pos: piece.pos,
      rotation: piece.rotation.rtr(),
      kind: piece.kind)
    (xs, ys, _) = rotated.info()

  for (x, y) in xs.zip(ys):
    if moveBound(x, y, game.board): return false
  true

func canMove(piece: Piece, game: Game, dx: int = 0, dy: int = 0): bool =
  let (xs, ys, _) = piece.info()
  for (x, y) in xs.zip(ys):
    let
      xp = x + dx
      yp = y + dy
    if moveBound(xp, yp, game.board): return false
  true

proc translate(piece: Piece, game: Game, dx: int = 0, dy: int = 0): bool =
  if piece.canMove(game, dx = dx, dy = dy):
    piece.pos[1] += dy
    piece.pos[0] += dx
    true
  else:
    false

func setPos(piece: Piece, pieceInfo: var PieceInfo): PieceInfo =
  let (x, y) = piece.pos
  for i in 0..<4:
    pieceInfo[0][i] = pieceInfo[0][i] + x
    pieceInfo[1][i] = pieceInfo[1][i] + y

  pieceInfo

func info(piece: Piece): PieceInfo =
  var pieceInfo: PieceInfo
  case piece.kind
  of I: pieceInfo = infoI()
  of J: pieceInfo = infoJ()
  of L: pieceInfo = infoL()
  of O: pieceInfo = infoO()
  of S: pieceInfo = infoS()
  of T: pieceInfo = infoT()
  of Z: pieceInfo = infoZ()
  pieceInfo = rotateInfo(pieceInfo, piece.rotation, piece.kind)
  setPos(piece, pieceInfo)

proc shadowPiece(piece: Piece, game: Game): Piece =
  var sp = Piece(pos: piece.pos, rotation: piece.rotation, kind: piece.kind)
  while sp.translate(game, dy = 1): discard
  sp

proc drawPiece(renderer: RP, game: Game) =
  let
    piece = game.workingPiece.currentPiece
    shadowPiece = shadowPiece(piece, game)
    shadowColor = uint32 0x585858
    (xs, ys, color) = piece.info()
    (shadowXs, shadowYs, _) = shadowPiece.info()

  renderer.drawTetromino(shadowXs, shadowYs, shadowColor)
  renderer.drawTetromino(xs, ys, color)

proc draw(renderer: RP, game: Game) =
  renderer.setDrawColor 0, 0, 0, 255
  renderer.clear()

  renderer.drawGrid(game)
  renderer.drawPiece(game)
  renderer.present()

proc updatePieceDown(game: Game): bool =
  game.workingPiece.dt = 0
  var piece = game.workingPiece.currentPiece
  if not piece.translate(game, dy = 1):
    game.setPiece piece.info()
    game.nextPiece()
    return true
  false

proc hardDropPiece(game: Game) =
  game.player.firstHard = false
  while not game.updatePieceDown(): discard

proc softDropPiece(game: Game) =
  game.player.firstSoft = false
  var piece = game.workingPiece.currentPiece
  discard piece.translate(game, dy = 1)

func rtl(rotation: Rotation): Rotation =
  case rotation
  of Rotation.TwoSeventy: Rotation.Zero
  else: succ rotation

func rtr(rotation: Rotation): Rotation =
  case rotation
  of Rotation.Zero: Rotation.TwoSeventy
  else: pred rotation

proc updateRotation(game: Game) =
  let rotation = game.workingPiece.currentPiece.rotation

  if game.player.firstRotation:
    game.player.firstRotation = false
    if game.inputs[Input.Rtr] and game.workingPiece.currentPiece.canRtr(game):
      game.workingPiece.currentPiece.rotation = rotation.rtr
    if game.inputs[Input.Rtl] and game.workingPiece.currentPiece.canRtl(game):
      game.workingPiece.currentPiece.rotation = rotation.rtl


proc updatePiece(game: Game, dt: float32) =
  let rotation = game.workingPiece.currentPiece.rotation

  game.workingPiece.dt += dt*game.workingPiece.speed

  if game.inputs[Input.Rtr] or game.inputs[Input.Rtl]: game.updateRotation()
  if game.inputs[Input.Soft]: softDropPiece(game)
  if game.inputs[Input.Hard] and game.player.firstHard: hardDropPiece(game)
  if game.workingPiece.dt >= Frame: discard updatePieceDown(game)

func isArr(player: Player): bool =
  player.arrTime * 72000000.0 > player.arr.float32()

func isDas(player: Player): bool =
  player.dasTime * 72000000.0 > player.das.float32()

proc time(player: Player, dt: float32) =
  player.arrTime += dt
  if player.isDas(): player.dasTime = 0
  if player.isArr(): player.dasTime += dt

proc updatePlayer(game: Game, dt: float32) =
  var player = game.player
  if player.firstMove or (player.isArr() and player.isDas()):
    if game.inputs[Input.Left]:
      discard game.workingPiece.currentPiece.translate(game, dx = -1)
    if game.inputs[Input.Right]:
      discard game.workingPiece.currentPiece.translate(game, dx = 1)

  if game.inputs[Input.Left] or game.inputs[Input.Right]:
      player.firstMove = false
      player.time(dt);

proc update(game: Game, dt: float32) =
  game.updatePlayer(dt)
  game.updatePiece(dt)

proc keyUp(game: Game, input: Input) =
  var player = game.player
  game.inputs[input] = false
  case input
  of Input.Rtr: game.player.firstRotation = true
  of Input.Rtl: game.player.firstRotation = true
  of Input.Left:
    game.player.firstMove = true
    player.arrTime = 0
    player.dasTime = 0
  of Input.Right:
    game.player.firstMove = true
    player.arrTime = 0
    player.dasTime = 0
  of Input.Soft: game.player.firstSoft = true
  of Input.Hard: game.player.firstHard = true
  else: discard

func toInput(scancode: ScanCode): Input =
  case scancode
  of ScanCode.SDL_SCANCODE_LEFT: return Input.Left
  of ScanCode.SDL_SCANCODE_RIGHT: return Input.Right
  of ScanCode.SDL_SCANCODE_SPACE: return Input.Hard
  of ScanCode.SDL_SCANCODE_DOWN: return Input.Soft
  of ScanCode.SDL_SCANCODE_Z: return Input.Rtl
  of ScanCode.SDL_SCANCODE_X: return Input.Rtr
  else: discard

type SDLException = object of Defect

template sdlFailIf(condition: typed, reason: string) =
  if condition: raise SDLException.newException(
    reason & ", SDL error " & $getError()
  )

proc main() =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 Initialization failed"
  defer: sdl2.quit()

  let window = createWindow(
    title = "TEST",
    x = SDL_WINDOWPOS_CENTERED,
    y = SDL_WINDOWPOS_CENTERED,
    w = WindowWidth,
    h = WindowHeight,
    flags = SDL_WINDOW_SHOWN
  )

  sdlFailIf window.isNil: "Could not create SDL2 Window"
  defer: window.destroy()

  let renderer = createRenderer(
    window = window,
    index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync or Renderer_TargetTexture
  )
  sdlFailIf renderer.isNil: "Renderer could not be created"
  defer: renderer.destroy()

  var
    running = true
    game = initGame()
    dt: float32 = 0

    counter: uint64 = 0
    previousCounter: uint64 = 0

  while running:
    dt = (counter - previousCounter).float() / getPerformanceCounter().float()
    previousCounter = counter
    counter = getPerformanceCounter()

    var event = defaultEvent

    while pollEvent(event):
      case event.kind
      of QuitEvent:
        running = false
        break

      of KeyDown:
        if event.key.keysym.scancode == ScanCode.SDL_SCANCODE_Q:
          running = false
          break
        if event.key.keysym.scancode == ScanCode.SDL_SCANCODE_LEFT:
          game.inputs[Input.Right] = false
        if event.key.keysym.scancode == ScanCode.SDL_SCANCODE_RIGHT:
          game.inputs[Input.Left] = false
        game.inputs[event.key.keysym.scancode.toInput] = true

      of KeyUp:
        game.keyUp(event.key.keysym.scancode.toInput)

      else:
        discard

    draw(renderer, game)
    game.update dt
    delay(uint32 1000.0/FPS)

randomize()
main()
