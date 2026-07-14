# mri_Qnitro — Manual

Sistema de nitro por item: instala NOS no veículo, dá boost com tecla dedicada, exige purga do sistema quando superaquece e habilita slipstream global com rastros de luz.

---

## Sumário

1. [Dependências](#dependências)
2. [Instalação](#instalação)
3. [Configuração](#configuração)
4. [Controles](#controles)
5. [Como funciona](#como-funciona)
6. [Slipstream](#slipstream)
7. [Entrypoints para outros recursos](#entrypoints-para-outros-recursos)
8. [Localização](#localização)
9. [Estrutura de arquivos](#estrutura-de-arquivos)

---

## Dependências

| Recurso | Obrigatório | Observação |
|---|---|---|
| `qbx_core` | Sim | `@qbx_core/modules/lib.lua` no cliente; `CreateUseableItem` e `Notify` |
| `ox_lib` | Sim | Locale, keybinds, callback, progress bar e `versionCheck` |
| `ox_inventory` | Sim | O servidor consome o item com `exports.ox_inventory:RemoveItem` |

---

## Instalação

1. Copie a pasta `mri_Qnitro` para `resources/`.
2. Adicione ao `server.cfg`:
   ```
   ensure mri_Qnitro
   ```
3. Cadastre o item `nitrous` no `ox_inventory` (`data/items.lua`). O nome do item está **fixo no código** (`server/main.lua`) e não é configurável.
4. Se `turboRequired` estiver ligado (padrão), os veículos precisam ter o upgrade de turbo instalado (mod toggle 18) para receber NOS.

---

## Configuração

O arquivo é `config/client.lua` e retorna uma tabela.

```lua
return {
    nitrousBoost = 3,
    turboRequired = true,
}
```

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `nitrousBoost` | number | Sim | Multiplicador aplicado à potência e ao torque do motor enquanto o boost está ativo (`SetVehicleEnginePowerMultiplier` / `SetVehicleEngineTorqueMultiplier`) |
| `turboRequired` | bool | Sim | Quando `true`, exige o upgrade de turbo no veículo para instalar e usar o NOS |

---

## Controles

Os dois keybinds são registrados via `lib.addKeybind` e ficam **desativados fora do banco do motorista**. Cada jogador pode remapeá-los nas configurações de teclado do FiveM.

| Tecla padrão | Nome | Ação |
|---|---|---|
| `LCONTROL` | `nitrous` | Segure para usar o NOS |
| `LSHIFT` | `purge` | Segure para purgar o sistema |

---

## Como funciona

1. **Instalar** — o jogador usa o item `nitrous` dentro do veículo. O servidor pede a validação ao cliente (`qbx_nitro:client:LoadNitrous`), que recusa se:
   - o jogador não está em um veículo, ou está em uma moto;
   - o veículo não tem turbo (quando `turboRequired = true`);
   - o jogador não é o motorista;
   - o veículo já tem NOS (`nitro > 0`).
2. Passando na validação, roda uma progress bar de 2,5 segundos ("Connecting NOS.."), cancelável. Ao concluir, o item é removido do inventário e o veículo recebe `nitro = 100`.
3. **Usar** — segurando a tecla de nitro, o boost liga: os multiplicadores de motor entram, a velocidade máxima vai para 999 e as chamas aparecem. O `nitro` cai **0,25 a cada 100 ms** (100 → 0 em cerca de 40 segundos de uso contínuo).
4. **Superaquecimento** — cada tick de uso também soma **+1** em `nitroPurge`. Ao chegar em **100**, o boost é cortado e o jogador é notificado de que precisa purgar o sistema.
5. **Purgar** — segurando a tecla de purga (fora do boost), sai vapor pelos lados do capô e o `nitroPurge` cai **1 a cada 100 ms**, até zerar. Só então o NOS volta a funcionar.
6. Depois de usar o boost há um **delay de 3 segundos** antes de poder acionar de novo.

Sair do banco do motorista ou do veículo interrompe boost e purga.

### State bags do veículo

Todo o estado fica no veículo, replicado para todos os clientes:

| Chave | Tipo | Descrição |
|---|---|---|
| `nitro` | number | Carga de NOS restante (0 a 100) |
| `nitroPurge` | number | Nível de superaquecimento (0 a 100). Em 100, o boost é bloqueado |
| `nitroFlames` | bool | Liga as chamas e o boost visual no veículo |
| `purgeNitro` | bool | Liga as partículas de vapor da purga |

---

## Slipstream

O recurso também habilita o slipstream (vácuo) global do GTA (`SetEnableVehicleSlipstreaming(true)`) e adiciona dois efeitos:

- **Rastro de luz** — enquanto um jogador está com o nitro ativo, todos os clientes veem trilhas de partícula (`veh_light_red_trail`) saindo das lanternas traseiras do veículo dele. A sincronização passa pelo evento `slipstream:sync`.
- **Tremor de câmera** — quando o seu veículo está pegando vácuo (`GetVehicleCurrentSlipstreamDraft` > 1.0), a câmera treme (`SKY_DIVING_SHAKE`).

O loop de sincronização roda a cada 1 segundo e imprime `Slip Stream Enabled` no console do cliente ao iniciar.

---

## Entrypoints para outros recursos

### Dar NOS a um veículo

Não há export. Outro recurso concede nitro escrevendo direto no state bag do veículo — é exatamente o que o `server/main.lua` faz ao consumir o item:

```lua
Entity(vehicle).state:set('nitro', 100, true)
```

### Ler a carga de um veículo

```lua
local charge = Entity(vehicle).state.nitro or 0
local overheat = Entity(vehicle).state.nitroPurge or 0
```

### Callback `qbx_nitro:client:LoadNitrous`

Valida o jogador e o veículo, roda a progress bar de instalação e retorna o **net id** do veículo, ou `false` se qualquer checagem falhar.

```lua
local netId = lib.callback.await('qbx_nitro:client:LoadNitrous', source)
```

### Evento `slipstream:sync` (servidor)

Retransmite o estado de slipstream de um veículo para todos os clientes, que ligam ou desligam os rastros de luz.

```lua
TriggerServerEvent('slipstream:sync', enabled, netId)
```

---

## Localização

As strings passam pelo locale do `ox_lib` (`ox_lib 'locale'` no manifest). Os arquivos ficam em `locales/`:

- `en.json` — inglês
- `fr.json` — francês
- `pt-br.json` — português do Brasil

O idioma ativo vem da convar:

```
setr ox:locale "pt-br"
```

---

## Estrutura de arquivos

```
mri_Qnitro/
├── client/
│   └── main.lua                    — keybinds, loops de boost e purga, handlers de state bag, partículas, slipstream e rastros
├── server/
│   └── main.lua                    — item usável nitrous, consumo no ox_inventory, sync do slipstream, versionCheck
├── config/
│   └── client.lua                  — nitrousBoost e turboRequired
├── locales/
│   ├── en.json
│   ├── fr.json
│   └── pt-br.json
├── stream/
│   └── veh_xs_vehicle_mods.ypt     — asset de partículas usado pelas chamas do nitro
└── fxmanifest.lua
```
