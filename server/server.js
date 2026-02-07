const { WebSocketServer } = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;
const MAX_ROOMS = 20;
const MIN_PLAYERS = 2;
const MAX_PLAYERS = 4;
const ROOM_CODE_LENGTH = 5;
const INITIAL_MONEY = 0;
const GOAL_BONUSES = [500, 300, 100, 0];

// ============================
// ボード定義（35マス、分岐1箇所）
// ============================
const BOARD = [
  // === メインルート前半 ===
  /* 0  */ { type:"start",  next:[1],     event:null },
  /* 1  */ { type:"normal", next:[2],     event:{ kind:"gain_money", amount:100, text:"お年玉をもらった！ +100円" } },
  /* 2  */ { type:"normal", next:[3],     event:null },
  /* 3  */ { type:"normal", next:[4],     event:{ kind:"lose_money", amount:50, text:"自販機でジュースを買った -50円" } },
  /* 4  */ { type:"normal", next:[5],     event:{ kind:"random_money", amount:200, min_amount:-100, text:"ギャンブル！" } },
  /* 5  */ { type:"normal", next:[6],     event:null },
  /* 6  */ { type:"normal", next:[7],     event:{ kind:"gain_money", amount:150, text:"バイト代をもらった！ +150円" } },
  /* 7  */ { type:"normal", next:[8],     event:null },
  /* 8  */ { type:"normal", next:[9],     event:{ kind:"lose_money", amount:100, text:"電車の切符をなくした -100円" } },
  /* 9  */ { type:"normal", next:[10],    event:null },

  // === 分岐点 ===
  /* 10 */ { type:"branch", next:[11,18], event:null, branch_labels:["山道コース","海道コース"] },

  // === 山道（ハイリスク・ハイリターン） ===
  /* 11 */ { type:"normal", next:[12],    event:{ kind:"gain_money", amount:300, text:"山で金鉱を発見！ +300円" } },
  /* 12 */ { type:"normal", next:[13],    event:{ kind:"lose_money", amount:200, text:"崖から落ちて治療費 -200円" } },
  /* 13 */ { type:"normal", next:[14],    event:null },
  /* 14 */ { type:"normal", next:[15],    event:{ kind:"random_money", amount:500, min_amount:-300, text:"山の賭場！大勝負！" } },
  /* 15 */ { type:"normal", next:[16],    event:null },
  /* 16 */ { type:"normal", next:[17],    event:{ kind:"gain_money", amount:200, text:"山菜を売った！ +200円" } },
  /* 17 */ { type:"normal", next:[25],    event:null },

  // === 海道（ローリスク・安定） ===
  /* 18 */ { type:"normal", next:[19],    event:{ kind:"gain_money", amount:100, text:"釣りで魚を売った！ +100円" } },
  /* 19 */ { type:"normal", next:[20],    event:null },
  /* 20 */ { type:"normal", next:[21],    event:{ kind:"gain_money", amount:100, text:"貝殻を拾って売った +100円" } },
  /* 21 */ { type:"normal", next:[22],    event:{ kind:"lose_money", amount:50, text:"日焼け止めを買った -50円" } },
  /* 22 */ { type:"normal", next:[23],    event:null },
  /* 23 */ { type:"normal", next:[24],    event:{ kind:"gain_money", amount:100, text:"サーフィン教室の報酬 +100円" } },
  /* 24 */ { type:"normal", next:[25],    event:null },

  // === 合流〜ゴール ===
  /* 25 */ { type:"normal", next:[26],    event:{ kind:"steal_money", amount:100, text:"トップの人からおすそ分け！" } },
  /* 26 */ { type:"normal", next:[27],    event:null },
  /* 27 */ { type:"normal", next:[28],    event:{ kind:"lose_money", amount:150, text:"税金を払った -150円" } },
  /* 28 */ { type:"normal", next:[29],    event:{ kind:"random_money", amount:300, min_amount:-200, text:"最後の大勝負！" } },
  /* 29 */ { type:"normal", next:[30],    event:null },
  /* 30 */ { type:"normal", next:[31],    event:{ kind:"gain_money", amount:100, text:"道端でお金を拾った +100円" } },
  /* 31 */ { type:"normal", next:[32],    event:null },
  /* 32 */ { type:"normal", next:[33],    event:{ kind:"lose_money", amount:50, text:"お賽銭を投げた -50円" } },
  /* 33 */ { type:"normal", next:[34],    event:null },
  /* 34 */ { type:"goal",   next:[],      event:{ kind:"goal_bonus", amount:0, text:"ゴール！" } },
];

// ============================
// サーバー起動
// ============================
const rooms = new Map();

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'GET' && req.url === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ rooms: rooms.size, max_rooms: MAX_ROOMS }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

const wss = new WebSocketServer({ server });
server.listen(PORT, () => {
  console.log(`Sugoroku Server started on port ${PORT}`);
});

// ============================
// WebSocket接続管理
// ============================
wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.roomCode = null;
  ws.playerIndex = -1;
  ws.playerName = '';

  ws.on('message', (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      handleMessage(ws, data);
    } catch (e) {
      console.error('JSON parse error:', e.message);
    }
  });

  ws.on('close', () => {
    handleDisconnect(ws);
  });

  ws.on('pong', () => {
    ws.isAlive = true;
  });
});

// ヘルスチェック (30秒間隔)
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      ws.terminate();
      return;
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(pingInterval);
});

// ============================
// メッセージハンドリング
// ============================
function handleMessage(ws, data) {
  switch (data.type) {
    case 'create_room':  createRoom(ws, data);        break;
    case 'join_room':    joinRoom(ws, data);           break;
    case 'start_game':   startGame(ws);                break;
    case 'roll_dice':    rollDice(ws);                 break;
    case 'branch_choice': handleBranchChoice(ws, data); break;
    case 'event_ack':    handleEventAck(ws);           break;
  }
}

// ============================
// ルーム管理
// ============================
function generateRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code;
  do {
    code = '';
    for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
  } while (rooms.has(code));
  return code;
}

function createRoom(ws, data) {
  if (ws.roomCode) return;
  if (rooms.size >= MAX_ROOMS) {
    sendTo(ws, { type: 'room_error', message: 'サーバーが満室です' });
    return;
  }

  const name = String(data.name || 'Player').substring(0, 8);
  const code = generateRoomCode();

  const room = {
    code,
    host: ws,
    players: [{
      ws, name, index: 0, position: 0, money: INITIAL_MONEY,
      finished: false, finishOrder: 0, disconnected: false,
    }],
    state: 'waiting',
    currentPlayerIndex: 0,
    turnPhase: 'idle',
    board: JSON.parse(JSON.stringify(BOARD)),
    finishCount: 0,
    pendingBranch: null,
  };

  rooms.set(code, room);
  ws.roomCode = code;
  ws.playerIndex = 0;
  ws.playerName = name;

  sendTo(ws, {
    type: 'room_created',
    code,
    players: getPlayersInfo(room),
  });
  console.log(`Room ${code} created by ${name}. Active rooms: ${rooms.size}`);
}

function joinRoom(ws, data) {
  if (ws.roomCode) return;

  const code = String(data.code || '').toUpperCase();
  const name = String(data.name || 'Player').substring(0, 8);
  const room = rooms.get(code);

  if (!room) {
    sendTo(ws, { type: 'room_error', message: 'ルームが見つかりません' });
    return;
  }
  if (room.state !== 'waiting') {
    sendTo(ws, { type: 'room_error', message: 'ゲームは既に開始されています' });
    return;
  }
  if (room.players.length >= MAX_PLAYERS) {
    sendTo(ws, { type: 'room_error', message: 'ルームが満員です' });
    return;
  }

  const playerIndex = room.players.length;
  room.players.push({
    ws, name, index: playerIndex, position: 0, money: INITIAL_MONEY,
    finished: false, finishOrder: 0, disconnected: false,
  });

  ws.roomCode = code;
  ws.playerIndex = playerIndex;
  ws.playerName = name;

  sendTo(ws, {
    type: 'room_joined',
    code,
    player_index: playerIndex,
    players: getPlayersInfo(room),
  });

  broadcastToRoom(room, {
    type: 'player_joined',
    players: getPlayersInfo(room),
  }, ws);

  console.log(`${name} joined room ${code}. Players: ${room.players.length}`);
}

function startGame(ws) {
  const room = rooms.get(ws.roomCode);
  if (!room) return;
  if (room.host !== ws) return;
  if (room.state !== 'waiting') return;
  if (room.players.length < MIN_PLAYERS) return;

  room.state = 'playing';
  room.currentPlayerIndex = 0;
  room.turnPhase = 'idle';

  broadcastToRoom(room, {
    type: 'game_started',
    board: room.board,
    players: getPlayersInfo(room),
    first_player: 0,
  });

  // 最初のターン開始
  setTimeout(() => {
    broadcastToRoom(room, {
      type: 'turn_start',
      current_player: room.currentPlayerIndex,
      players: getPlayersInfo(room),
    });
  }, 500);

  console.log(`Game started in room ${room.code}`);
}

// ============================
// ターン管理
// ============================
function rollDice(ws) {
  const room = rooms.get(ws.roomCode);
  if (!room || room.state !== 'playing') return;
  if (ws.playerIndex !== room.currentPlayerIndex) return;
  if (room.turnPhase !== 'idle') return;

  room.turnPhase = 'rolling';
  const diceValue = Math.floor(Math.random() * 6) + 1;

  broadcastToRoom(room, {
    type: 'dice_result',
    player_index: ws.playerIndex,
    value: diceValue,
  });

  // 移動処理を少し遅延（クライアントのアニメーション用）
  setTimeout(() => {
    movePlayer(room, ws.playerIndex, diceValue);
  }, 1500);
}

function movePlayer(room, playerIndex, steps) {
  const player = room.players[playerIndex];
  let current = player.position;
  const path = [];

  for (let i = 0; i < steps; i++) {
    const square = room.board[current];
    if (square.type === 'goal') break;
    if (square.next.length === 0) break;

    if (square.next.length > 1) {
      // 分岐点 - プレイヤーの選択を待つ
      player.position = current; // 分岐マスまで位置を更新
      room.turnPhase = 'branch_choice';
      room.pendingBranch = { playerIndex, remainingSteps: steps - i, branchSquareIndex: current, path };

      broadcastToRoom(room, {
        type: 'player_moving',
        player_index: playerIndex,
        path: path.slice(),
      });

      sendTo(player.ws, {
        type: 'branch_choice_request',
        square_index: current,
        options: square.next.map((nextIdx, oi) => ({
          next: nextIdx,
          label: square.branch_labels ? square.branch_labels[oi] : `ルート${oi + 1}`,
        })),
      });
      return;
    }

    current = square.next[0];
    path.push(current);

    // ゴールに到達したら停止
    if (room.board[current].type === 'goal') break;
  }

  // 移動完了
  player.position = current;
  room.turnPhase = 'moving';

  broadcastToRoom(room, {
    type: 'player_moving',
    player_index: playerIndex,
    path,
  });

  // 移動アニメーション後にイベント処理
  const animDelay = Math.max(path.length * 400, 500);
  setTimeout(() => {
    applySquareEvent(room, playerIndex);
  }, animDelay);
}

function handleBranchChoice(ws, data) {
  const room = rooms.get(ws.roomCode);
  if (!room || room.state !== 'playing') return;
  if (room.turnPhase !== 'branch_choice') return;
  if (!room.pendingBranch || room.pendingBranch.playerIndex !== ws.playerIndex) return;

  const choice = Number(data.choice);
  const branchSquareIndex = room.pendingBranch.branchSquareIndex;
  const branchSquare = room.board[branchSquareIndex];
  if (choice < 0 || choice >= branchSquare.next.length) return;

  const { remainingSteps, path: prevPath } = room.pendingBranch;
  room.pendingBranch = null;

  const player = room.players[ws.playerIndex];
  let current = branchSquare.next[choice];
  const path = [current];

  // 残りの歩数を消化（分岐を選んだ1歩分はカウント済み）
  for (let i = 1; i < remainingSteps; i++) {
    const square = room.board[current];
    if (square.type === 'goal') break;
    if (square.next.length === 0) break;

    if (square.next.length > 1) {
      // 二重分岐（MVPでは発生しないが念のため）
      current = square.next[0];
    } else {
      current = square.next[0];
    }
    path.push(current);
    if (room.board[current].type === 'goal') break;
  }

  player.position = current;
  room.turnPhase = 'moving';

  broadcastToRoom(room, {
    type: 'player_moving',
    player_index: ws.playerIndex,
    path,
  });

  const animDelay = Math.max(path.length * 400, 500);
  setTimeout(() => {
    applySquareEvent(room, ws.playerIndex);
  }, animDelay);
}

function applySquareEvent(room, playerIndex) {
  const player = room.players[playerIndex];
  const square = room.board[player.position];

  // ゴール処理
  if (square.type === 'goal') {
    if (!player.finished) {
      player.finished = true;
      room.finishCount++;
      player.finishOrder = room.finishCount;
      const bonus = GOAL_BONUSES[room.finishCount - 1] || 0;
      const moneyBefore = player.money;
      player.money += bonus;

      broadcastToRoom(room, {
        type: 'player_finished',
        player_index: playerIndex,
        finish_order: room.finishCount,
        bonus,
        money_before: moneyBefore,
        money_after: player.money,
      });

      // 全員ゴールしたか、残り1人かチェック
      const activePlayers = room.players.filter(p => !p.finished && !p.disconnected);
      if (activePlayers.length <= 0) {
        endGame(room);
        return;
      }
    }
    // ゴール済みプレイヤーのターンをスキップして次へ
    advanceTurn(room);
    return;
  }

  // イベントなし
  if (!square.event) {
    room.turnPhase = 'idle';
    advanceTurn(room);
    return;
  }

  // イベント処理
  const event = square.event;
  const moneyBefore = player.money;
  let moneyChange = 0;

  switch (event.kind) {
    case 'gain_money':
      moneyChange = event.amount;
      break;
    case 'lose_money':
      moneyChange = -event.amount;
      break;
    case 'random_money':
      moneyChange = randomInt(event.min_amount, event.amount);
      break;
    case 'steal_money': {
      // 最も所持金が多いプレイヤーから奪う（自分以外）
      let richest = null;
      for (const p of room.players) {
        if (p.index === playerIndex) continue;
        if (p.disconnected) continue;
        if (!richest || p.money > richest.money) richest = p;
      }
      if (richest && richest.money > 0) {
        const stealAmount = Math.min(event.amount, richest.money);
        richest.money -= stealAmount;
        moneyChange = stealAmount;
      }
      break;
    }
  }

  player.money += moneyChange;
  room.turnPhase = 'event';

  broadcastToRoom(room, {
    type: 'event_triggered',
    player_index: playerIndex,
    square_index: player.position,
    event: { ...event, actual_amount: moneyChange },
    money_before: moneyBefore,
    money_after: player.money,
    players: getPlayersInfo(room),
  });
}

function handleEventAck(ws) {
  const room = rooms.get(ws.roomCode);
  if (!room || room.state !== 'playing') return;
  if (ws.playerIndex !== room.currentPlayerIndex) return;
  if (room.turnPhase !== 'event') return;

  room.turnPhase = 'idle';
  advanceTurn(room);
}

function advanceTurn(room) {
  const totalPlayers = room.players.length;
  let nextIndex = (room.currentPlayerIndex + 1) % totalPlayers;
  let attempts = 0;

  // ゴール済み・切断済みのプレイヤーをスキップ
  while (attempts < totalPlayers) {
    const p = room.players[nextIndex];
    if (!p.finished && !p.disconnected) break;
    nextIndex = (nextIndex + 1) % totalPlayers;
    attempts++;
  }

  if (attempts >= totalPlayers) {
    endGame(room);
    return;
  }

  room.currentPlayerIndex = nextIndex;
  room.turnPhase = 'idle';

  broadcastToRoom(room, {
    type: 'turn_start',
    current_player: nextIndex,
    players: getPlayersInfo(room),
  });
}

function endGame(room) {
  room.state = 'finished';

  // ランキング: ゴール順 → 所持金順
  const rankings = room.players
    .filter(p => !p.disconnected)
    .sort((a, b) => {
      if (a.finished && !b.finished) return -1;
      if (!a.finished && b.finished) return 1;
      if (a.finished && b.finished) return a.finishOrder - b.finishOrder;
      return b.money - a.money;
    })
    .map((p, i) => ({
      rank: i + 1,
      player_index: p.index,
      name: p.name,
      money: p.money,
      finished: p.finished,
      finish_order: p.finishOrder,
    }));

  broadcastToRoom(room, {
    type: 'game_over',
    rankings,
  });

  // ルーム削除を遅延
  setTimeout(() => destroyRoom(room.code), 5000);
  console.log(`Game ended in room ${room.code}`);
}

// ============================
// 切断処理
// ============================
function handleDisconnect(ws) {
  if (!ws.roomCode) return;
  const room = rooms.get(ws.roomCode);
  if (!room) return;

  if (room.state === 'waiting') {
    // 待機中: プレイヤーを削除
    room.players = room.players.filter(p => p.ws !== ws);
    // インデックス再割当
    room.players.forEach((p, i) => {
      p.index = i;
      p.ws.playerIndex = i;
    });

    if (room.players.length === 0) {
      destroyRoom(room.code);
      return;
    }

    // ホストが抜けた場合、次のプレイヤーをホストに
    if (room.host === ws) {
      room.host = room.players[0].ws;
      broadcastToRoom(room, {
        type: 'host_changed',
        new_host_index: 0,
      });
    }

    broadcastToRoom(room, {
      type: 'player_left',
      players: getPlayersInfo(room),
    });
  } else if (room.state === 'playing') {
    // プレイ中: 切断フラグを立てる
    const player = room.players.find(p => p.ws === ws);
    if (player) {
      player.disconnected = true;
      broadcastToRoom(room, {
        type: 'player_disconnected',
        player_index: player.index,
      });

      // 切断者のターン中なら次へ進める
      if (room.currentPlayerIndex === player.index) {
        room.turnPhase = 'idle';
        advanceTurn(room);
      }
    }

    // 全員切断チェック
    const activePlayers = room.players.filter(p => !p.disconnected);
    if (activePlayers.length <= 1) {
      if (activePlayers.length === 1) {
        endGame(room);
      } else {
        destroyRoom(room.code);
      }
    }
  } else {
    // finished状態
    const allDisconnected = room.players.every(p => p.disconnected || p.ws === ws);
    if (allDisconnected) destroyRoom(room.code);
  }

  ws.roomCode = null;
  ws.playerIndex = -1;
  console.log(`${ws.playerName} disconnected`);
}

function destroyRoom(code) {
  const room = rooms.get(code);
  if (!room) return;

  room.players.forEach(p => {
    if (p.ws) {
      p.ws.roomCode = null;
      p.ws.playerIndex = -1;
    }
  });

  rooms.delete(code);
  console.log(`Room ${code} destroyed. Active rooms: ${rooms.size}`);
}

// ============================
// ユーティリティ
// ============================
function sendTo(ws, data) {
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

function broadcastToRoom(room, data, excludeWs) {
  for (const p of room.players) {
    if (p.ws !== excludeWs && !p.disconnected) {
      sendTo(p.ws, data);
    }
  }
}

function getPlayersInfo(room) {
  return room.players.map(p => ({
    index: p.index,
    name: p.name,
    position: p.position,
    money: p.money,
    finished: p.finished,
    finish_order: p.finishOrder,
    disconnected: p.disconnected,
    is_host: p.ws === room.host,
  }));
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
