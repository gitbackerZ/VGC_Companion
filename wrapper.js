import { BattleStreams, Dex } from '@pkmn/sim';

let stream = null;
let logQueue = [];

// --- Safe Dex Lookup Patch (Applies to base and modded Dex environments) ---
function patchDexInstance(targetDex) {
  try {
    if (targetDex && targetDex.species) {
      if (!targetDex.species._isPatched) {
        const origGet = targetDex.species.get;
        if (typeof origGet === 'function') {
          targetDex.species.get = function(name) {
            const res = origGet.call(this, name);
            if (res && res.exists !== false) return res;
            return { 
              exists: true, 
              name: typeof name === 'string' ? name : 'Unknown', 
              num: 0, 
              types: ['Normal'], 
              baseStats: {hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100}, 
              abilities: {0: 'Pressure'} 
            };
          };
        }
        
        const origGetByID = targetDex.species.getByID;
        if (typeof origGetByID === 'function') {
          targetDex.species.getByID = function(id) {
            const res = origGetByID.call(this, id);
            if (res && res.exists !== false) return res;
            return { 
              exists: true, 
              name: typeof id === 'string' ? id : 'Unknown', 
              num: 0, 
              types: ['Normal'], 
              baseStats: {hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100}, 
              abilities: {0: 'Pressure'} 
            };
          };
        }
        targetDex.species._isPatched = true;
      }
    }
  } catch (e) {
    // Silent catch for safety
  }
}

// Patch root Dex immediately upon load
patchDexInstance(Dex);

globalThis.startVGCBattle = function(format, p1Team, p2Team) {
  try {
    const activeDex = Dex.forFormat(format);
    patchDexInstance(activeDex);
  } catch (e) {}

  stream = new BattleStreams.BattleStream();
  logQueue = [];

  (async () => {
    try {
      for await (const chunk of stream) {
        logQueue.push(chunk);
      }
    } catch (err) {
      logQueue.push(`|error|[Engine Initialization Error] ${err.message}`);
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

// --- Champions Mod Data API Helpers ---

// Get all species filtered through the champions mod data and rule set
globalThis.getSpeciesList = function(format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const list = activeDex.species.all()
    .filter(s => s.num > 0 && (!s.isNonstandard || s.isNonstandard === 'Past' || s.id.includes('antique') || s.id.includes('masterpiece')))
    .map(s => ({
      name: s.name,
      id: s.id,
      types: s.types,
      baseStats: s.baseStats,
      abilities: Object.values(s.abilities || {})
    }));
  return JSON.stringify(list);
};

// Get all competitive moves filtered through the champions mod data and rule set
globalThis.getMoveList = function(format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const list = activeDex.moves.all()
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

// Get items filtered through the champions mod data and rule set
globalThis.getItemList = function(format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const list = activeDex.items.all()
    .filter(i => !i.isNonstandard && i.num > 0)
    .map(i => ({
      name: i.name,
      id: i.id,
      desc: i.shortDesc
    }));
  return JSON.stringify(list);
};
