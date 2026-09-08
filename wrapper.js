import { BattleStreams, Dex } from '@pkmn/sim';

let stream = null;
let logQueue = [];

globalThis.startVGCBattle = function(format, p1Team, p2Team) {
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

function safeGetSpecies(dex, name) {
  try {
    const s = dex.species.get(name);
    if (s && s.exists !== false) return s;
  } catch (e) {}
  return {
    name: typeof name === 'string' ? name : 'Unknown',
    id: '',
    num: 0,
    types: ['Normal'],
    baseStats: { hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100 },
    abilities: { 0: 'Pressure' }
  };
}

globalThis.getBaseSpeciesList = globalThis.getSpeciesList = function(format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
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

globalThis.getPokemon = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const s = safeGetSpecies(activeDex, name);
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

globalThis.getAbilitiesForPokemon = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const s = safeGetSpecies(activeDex, name);
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

globalThis.getFormesForSpecies = function(baseName, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const baseSpecies = safeGetSpecies(activeDex, baseName);
  const formes = [{
    name: baseSpecies.name,
    types: baseSpecies.types,
    num: baseSpecies.num
  }];
  if (baseSpecies.otherFormes) {
    for (const fName of baseSpecies.otherFormes) {
      const f = safeGetSpecies(activeDex, fName);
      if (f && f.name) {
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

globalThis.getMovesForSpecies = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
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

globalThis.getGenderRate = function(name, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const s = safeGetSpecies(activeDex, name);
  if (s.genderRatio) {
    if (s.genderRatio.M === 0 && s.genderRatio.F === 0) return JSON.stringify(-1);
    if (s.genderRatio.F === 1) return JSON.stringify(8);
    return JSON.stringify(4);
  }
  return JSON.stringify(4);
};

globalThis.getMegaFormForHeldItem = function(name, item, format = 'gen9championsdoublescustomgame') {
  const activeDex = Dex.forFormat(format);
  const s = safeGetSpecies(activeDex, name);
  let megaForm = null;
  if (s.otherFormes) {
    for (const fName of s.otherFormes) {
      const f = safeGetSpecies(activeDex, fName);
      if (f && f.requiredItem && f.requiredItem.toLowerCase() === item.toLowerCase()) {
        megaForm = f.name;
        break;
      }
    }
  }
  return JSON.stringify(megaForm);
};

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
