import { BattleStreams } from '@pkmn/sim';

let stream = null;
let logQueue = [];

globalThis.startVGCBattle = function(format, p1Team, p2Team) {
  stream = new BattleStreams.BattleStream();
  logQueue = [];

  // Listen to output stream
  (async () => {
    for await (const chunk of stream) {
      logQueue.push(chunk);
    }
  })();

  stream.write(`>start {"formatid":"${format}"}`);
  stream.write(`>player p1 {"name":"Player 1", "team":"${p1Team}"}`);
  stream.write(`>player p2 {"name":"Player 2", "team":"${p2Team}"}`);
};

globalThis.sendAction = function(actionString) {
  if (stream) stream.write(actionString);
};

// Expose log queue to Dart
globalThis.getLogs = function() {
  const logs = [...logQueue];
  logQueue = []; // Clear queue after reading
  return JSON.stringify(logs);
};
