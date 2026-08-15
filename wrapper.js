import { BattleStreams, Dex } from '@pkmn/sim';

let stream = null;
let logQueue = [];

globalThis.startVGCBattle = function(format, p1Team, p2Team) {
  stream = new BattleStreams.BattleStream();
  logQueue = [];

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

globalThis.getLogs = function() {
  const logs = [...logQueue];
  logQueue = [];
  return JSON.stringify(logs);
};

// --- Pokédex Data API Helpers ---

// Get all legal standard species (Name, Types, Base Stats, Abilities)
globalThis.getSpeciesList = function() {
  const list = Dex.species.all()
    .filter(s => s.num > 0 && !s.isNonstandard)
    .map(s => ({
      name: s.name,
      id: s.id,
      types: s.types,
      baseStats: s.baseStats,
      abilities: Object.values(s.abilities)
    }));
  return JSON.stringify(list);
};

// Get all standard competitive moves
globalThis.getMoveList = function() {
  const list = Dex.moves.all()
    .filter(m => !m.isNonstandard && m.num > 0)
    .map(m => ({
      name: m.name,
      id: m.id,
      type: m.type,
      category: m.category,
      basePower: m.basePower,
      accuracy: m.accuracy,
      pp: m.pp
    }));
  return JSON.stringify(list);
};

// Get standard items
globalThis.getItemList = function() {
  const list = Dex.items.all()
    .filter(i => !i.isNonstandard && i.num > 0)
    .map(i => ({
      name: i.name,
      id: i.id,
      desc: i.shortDesc
    }));
  return JSON.stringify(list);
};
