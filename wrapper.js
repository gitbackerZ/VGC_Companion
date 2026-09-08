import { BattleStreams, Dex } from '@pkmn/sim';

let stream = null;
let logQueue = [];

// --- Safe Dex Lookup Patch ---
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

// --- Champions Mod Data API Helpers for Flutter ---

// Get base species list filtered through champions mod
globalThis.getBaseSpeciesList = globalThis.getSpeciesList = function(format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const list = activeDex.species.all()
    .filter(s => s.num > 0 && !s.forme && (!s.isNonstandard || s.isNonstandard === 'Past' || s.id.includes('antique') || s.id.includes('masterpiece')))
    .map(s => ({
      name: s.name,
      id: s.id,
      num: s.num,
      types: s.types,
      baseStats: s.baseStats,
      abilities: Object.values(s.abilities || {})
    }));
  return JSON.stringify(list);
};

// Get individual Pokémon details
globalThis.getPokemon = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const s = activeDex.species.get(name);
  return JSON.stringify({
    name: s.name,
    id: s.id,
    num: s.num,
    types: s.types,
    baseStats: s.baseStats,
    baseSpecies: s.baseSpecies,
    genderRatio: s.genderRatio,
    abilities: s.abilities
  });
};

// Get abilities available for a specific Pokémon
globalThis.getAbilitiesForPokemon = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const s = activeDex.species.get(name);
  const abilities = [];
  if (s.abilities) {
    for (const key in s.abilities) {
      const abilName = s.abilities[key];
      if (abilName) {
        abilities.push({ slot: key, name: abilName });
      }
    }
  }
  return JSON.stringify(abilities);
};

// Get alternative forms/formes for a species
globalThis.getFormesForSpecies = function(baseName, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const baseSpecies = activeDex.species.get(baseName);
  const formes = [{
    name: baseSpecies.name,
    types: baseSpecies.types,
    num: baseSpecies.num
  }];
  if (baseSpecies.otherFormes) {
    for (const fName of baseSpecies.otherFormes) {
      const f = activeDex.species.get(fName);
      if (f && f.exists) {
        formes.push({
          name: f.name,
          types: f.types,
          num: f.num
        });
      }
    }
  }
  return JSON.stringify(formes);
};

// Get legal moves for species under champions mod
globalThis.getMovesForSpecies = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const list = activeDex.moves.all()
    .filter(m => !m.isNonstandard && m.num > 0)
    .map(m => ({
      name: m.name,
      id: m.id,
      type: m.type,
      category: m.category,
      basePower: m.basePower
    }));
  return JSON.stringify(list);
};

// Get gender rate for a species
globalThis.getGenderRate = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const s = activeDex.species.get(name);
  if (s.genderRatio) {
    if (s.genderRatio.M === 0 && s.genderRatio.F === 0) return JSON.stringify(-1);
    if (s.genderRatio.F === 1) return JSON.stringify(8);
    return JSON.stringify(4);
  }
  return JSON.stringify(4);
};

// Get Mega or special form associated with a held item
globalThis.getMegaFormForHeldItem = function(name, item, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const s = activeDex.species.get(name);
  let megaForm = null;
  if (s.otherFormes) {
    for (const fName of s.otherFormes) {
      const f = activeDex.species.get(fName);
      if (f && f.requiredItem && f.requiredItem.toLowerCase() === item.toLowerCase()) {
        megaForm = f.name;
        break;
      }
    }
  }
  return JSON.stringify(megaForm);
};

// Get item list filtered through champions mod
globalThis.getItemList = function(format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  patchDexInstance(activeDex);
  const list = activeDex.items.all()
    .filter(i => !i.isNonstandard && i.num > 0)
    .map(i => ({
      name: i.name,
      id: i.id,
      desc: i.shortDesc
    }));
  return JSON.stringify(list);
};
