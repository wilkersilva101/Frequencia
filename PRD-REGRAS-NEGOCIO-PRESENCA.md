# PRD — Regras de Negócio do Módulo `presenca` (Intranet legado) e Replicação no Frequencia

**Data:** 2026-09-15
**Origem:** varredura de ponta a ponta do módulo `presenca` do sistema Intranet legado (`/home/davi.queiroz/Área de trabalho/workspace_integração/intranet/src/modules/presenca`, 176 arquivos Java + JSPs de suporte), feita em 3 investigações paralelas cobrindo: (1) motor de cálculo e consolidação, (2) tipos de usuário e exceções, (3) estações/intervenções/entidades secundárias. Cada regra foi cruzada contra o que já está documentado em `SPRINT-PLAN.md` (Sprints 9-21) para separar o que já é conhecido do que é **novo**.

**Por que este documento existe:** o PRD original (`PRD-POC-API-PONTO.md`) cobre só o protocolo de comunicação com a EstaçãoPonto (PoC inicial, Sprints 1-7). O SPRINT-PLAN.md documenta o que foi *implementado*, mas várias decisões de "fora de escopo" foram tomadas sem o nível de detalhe fino que esta varredura revelou. Este documento é a fonte de verdade de **todas as regras de negócio reais encontradas no legado**, implementadas ou não, para orientar o backlog futuro do Frequencia com precisão.

---

## 1. Metodologia e limitações

- Leitura direta do código-fonte Java (beans, DAOs, services, actions, jobs, validators, enums, filters, tags) e de 2 JSPs de suporte (`PONTO_FACULTATIVO.jsp`, `TRABALHO_REMOTO_COVID.jsp`) que contêm lógica de negócio real não replicada em nenhuma classe Java.
- **Não é uma leitura de 100% dos 176 arquivos linha a linha** — é uma varredura dirigida, priorizando arquivos com maior densidade de regra de negócio (beans centrais, services, jobs) sobre arquivos de infraestrutura pura (formatters, tags de exibição simples).
- Cada regra foi confirmada contra o `SPRINT-PLAN.md` para status real de implementação — não presumido.
- **Dois achados de "bug morto" no próprio legado** (detalhados na seção 7) significam que replicar 100% fielmente nem sempre é o objetivo certo — algumas partes do código legado estão desativadas em produção (comentadas, `if (false)`) e não devem ser copiadas como se fossem comportamento vigente.

---

## 2. Tipos de usuário / atores do sistema

O módulo `presenca` não modela "tipo de usuário" como uma dimensão única — são **quatro dimensões independentes** que se combinam:

### 2.1 Categoria de vínculo (`CategoriaVinculoEnum`, módulo `tjpi`)

- Enum completo tem **23 valores**, mas só **7 são expostos nas telas** do módulo presença (hardcoded em `RegimeActions`/`FrequentadorActions`): `SERVIDOR_CARREIRA`, `CARGO_COMISSIONADO`, `ESTAGIARIO`, `RESIDENTE`, `TERCEIRIZADO`, `AUXILIAR_DA_JUSTICA`, `CEDIDO`.
- Os dados **reais persistidos em produção** (`presenca_regime_categoriavinculo`) usam só **6 códigos** — `RESIDENTE` nunca foi usado de fato, apesar de sempre ter sido uma opção válida na tela.
- **Decisão já tomada no Frequencia** (Sprint 11.6): `Regime::CATEGORIAS_DISPONIVEIS` usa os 6 códigos reais. Este PRD registra a divergência para decisão consciente — não é erro, é uma escolha (replicar dado real vs. replicar toda opção de tela).

### 2.2 Regime aplicado (`TipoRegimeFrequentadorEnum`)

- `OFICIAL` (ordem 0), `DIFERENCIADO` (ordem 1), `TEMPORARIO` (ordem 2, **nunca instanciado em nenhum lugar do código legado** — é letra morta na prática, apesar de selecionável na UI).
- Um frequentador pode ter múltiplos `RegimeFrequentador` vigentes simultaneamente (ex: um OFICIAL + um DIFERENCIADO); o regime **efetivo no dia é sempre o de maior `ordem`** — DIFERENCIADO sempre sobrepõe OFICIAL quando coexistem.
- Já implementado no Frequencia (Sprint 16.3), mas sem registro de que TEMPORARIO é morto.

### 2.3 Papéis de acesso ao sistema (`PresencaRolesEnum` / `PresencaProfilesEnum`)

11 roles granulares + 7 perfis (bundles de roles) — **nenhuma parte disso está implementada no Frequencia hoje** (que usa só `admin: true/false` binário +, desde a Sprint 23, Rolify com 3 roles genéricas `admin`/`gestor`/`operador`, não mapeadas 1:1 com as 11 do legado):

| Role legado | Efeito |
|---|---|
| `PRESENCA_VISUALIZA_ESTACOES` / `PRESENCA_CONTROLA_ESTACOES` / `PRESENCA_GERENCIA_ESTACAO` / `PRESENCA_CADASTRA_ESTACAO` | granularidade de acesso a estações (ver/controlar remotamente/gerenciar/cadastrar) |
| `PRESENCA_GERENCIA_EXCEPCIONAIS` | gerência de Direitos, Feriados, Dias Excepcionais, Registros Manuais, Regimes |
| `PRESENCA_VISUALIZA_EXCEPCIONAIS` | só visualização do que a role acima gerencia |
| `PRESENCA_GERENCIA_FREQUENTADORES` | gerência de frequentadores + as 4 flags administrativas de `CalculoDiario` (seção 6) |
| `PRESENCA_VISUALIZA_FREQUENTADORES` | acesso geral de leitura a frequência de qualquer frequentador |
| `PRESENCA_VISUALIZA_FREQUENTADORES_TERCEIRIZADOS` | acesso de leitura **restrito só a frequentadores `TERCEIRIZADO`** |
| `PRESENCA_VISUALIZA_GESTOR_INDIVIDUAL` / `PRESENCA_GERENCIA_GESTOR_INDIVIDUAL` | gestão da entidade `GestorIndividual` (seção 4.5) |
| `PRESENCA_GERENCIA_RETIFICADORES` | criar/editar retificadores de banco de horas |
| `PRESENCA_CADASTRO_DIGITAL` | cadastrar digital biométrica via estação |

Perfis: `PRESENCA_ADMIN` (excepcionais+frequentadores), `PRESENCA_ADMIN_EXCEPCIONAIS`, `PRESENCA_ADMIN_FREQUENTADORES`, `PRESENCA_OPERADOR` (estações), `PRESENCA_PROGRAMADOR` (tudo), `PRESENCA_VISUALIZADOR_FREQUENTADORES` (inclui terceirizados), `PRESENCA_VISUALIZADOR_EXCEPCIONAIS`.

### 2.4 Funções/lotações especiais (hardcoded por título/caminho, não por enum)

`Frequentador.java` tem 8 métodos booleanos (`isSecretario`, `isCoordenadorGeral`, `isOficialJustica`, `isAssessorMagistrado1Grau`, `isAuxiliarJustica`, `isLotadoGabineteDesembargador`, `isLotadoGabinetePresidenciaVicePresidencia`, `isLotadoGabineteCorregedoria`) que checam **texto do título do cargo** ou **caminho da lotação** (ex: título começa com `"Coordenador"`, caminho começa com `"TJ-PI > Gab. Des"`). A combinação desses 8 (`isPermitidoModalidadeOcorrencias`) decide quem pode usar a modalidade `OCORRENCIAS` de registro — **não mapeia 1:1 pra categoria de vínculo**, é uma regra de negócio genuinamente complexa que precisa virar configuração no Frequencia, não `if/else` hardcoded.

### 2.5 `GestorIndividual` — ator especial fora da hierarquia

Vincula um gestor a um frequentador específico **fora da árvore organizacional** ("gestão excepcional", segundo o próprio Javadoc do legado). Um frequentador pode ter múltiplos gestores individuais ativos. Soft-delete (`ativo`/`dataExclusao`), nunca hard-delete. Já modelado no Frequencia como tela (`admin/gestores_individuais`), mas sem confirmação de que a regra de **autorização** que usa isso (seção 3) foi portada.

---

## 3. Regra central de autorização — quem pode ver/gerenciar a frequência de quem

**Não documentada em nenhuma nota do SPRINT-PLAN — provavelmente a regra de autorização mais importante do módulo.**

`RegistroFrequenciaValidator.frequentador` (legado) define, em cascata (primeira condição que casar libera acesso):

1. É o próprio frequentador (login bate);
2. Tem role `PRESENCA_VISUALIZA_FREQUENTADORES` (acesso geral);
3. Tem role `PRESENCA_VISUALIZA_FREQUENTADORES_TERCEIRIZADOS` **e** o frequentador-alvo é `TERCEIRIZADO`;
4. É `GestorIndividual` vinculado ativo daquele frequentador;
5. Sobe a árvore hierárquica de Órgãos a partir da lotação atual do frequentador, checando se o usuário logado é gestor atual/substituto/excepcional de algum órgão na cadeia.

Se nada casar até a raiz da árvore, acesso negado.

Regra irmã de **elegibilidade pra desconsiderar um dia** (`podeDesconsiderarFrequencia`, `RegistroFrequenciaServices.java:91-108`): o dia precisa ter registros, não pode ser falta/meta-zero/já-descontado-em-folha; nenhum registro do dia pode já estar desconsiderado; e quem aciona precisa ser gestor do órgão do alvo — **mas não pode desconsiderar o próprio ponto** (bloqueio explícito, mesmo sendo gestor de si mesmo).

**Status no Frequencia:** ❌ não implementado. A Sprint 19 implementou o *efeito* de desconsiderar/deferir/indeferir, mas não a regra completa de quem tem permissão de acionar isso.

---

## 4. Motor de cálculo diário — regras finas não documentadas

*(Ver `SPRINT-PLAN.md` Sprint 16 para o que já está implementado — meta semanal, dispatch por modalidade, `Ocorrencias`/`EntradasESaidas`/`PrimeiraEntradaUltimaSaida`. Esta seção cobre só o que a varredura encontrou de novo.)*

### 4.1 Corte histórico de estratégia (dez/2018)
Regime `HORAS`: dias antes de 01/12/2018 usam `PrimeiraEntradaUltimaSaidaOldV2` (estratégia diferente); depois, `PrimeiraEntradaUltimaSaidaV2`. O Frequencia sempre usa a lógica "nova" — aceitável apenas se nunca precisar recalcular datas anteriores a dez/2018.

### 4.2 Tolerância de 15 minutos — mecânica exata
`CalculoStrategyV2.ajustarSegundosTrabalhados` (desde 01/05/2017, se `!liberadoLimitacaoInicioHoraExtra`): **não é** "só credita excedente acima de 15min" — é uma **subtração fixa de 15min sobre todo o excedente**, sempre, mesmo quando o excedente é muito maior que 15min. Deliberadamente não implementado no Frequencia; este é o detalhe exato caso seja implementado no futuro.

### 4.3 Cap diário de banco de horas — não é fixo em 2h
`CalculoStrategyV2.getMaximoBancoHorasioDiarioPermitido`:
- Se `liberadoBloqueioMaxHoraExtra`: sem limite.
- Senão: cap = config do regime (`maximoBancoHorasDiarioEmSegundos`), **exceto** regra "GCET": se `meta >= 8h` e a data está entre 01/12/2018 e 26/10/2022, cap vira **45 minutos** (2700s), independente do configurado.
- Para as 3 datas exatas 21/22/23-11-2022: cap sempre `99999s` (~27h48min) — banco de horas efetivamente liberado nesses 3 dias.
- Endpoint administrativo `LiberarBloqueioMaxHoraExtra` (role `PRESENCA_GERENCIA_FREQUENTADORES`) confirma texto de que o limite hardcoded padrão é **2 horas/dia**.

### 4.4 Limitação de acúmulo por frequentador (não por regime)
`Frequentador.isLimitarAcumuloHoras()` — se ativo, o trabalhado do dia é recalculado "para efeito de cálculo": se saldo acumulado do mês (até o dia anterior) é ≥ 0, trabalhado é limitado exatamente à meta (zera hora extra); se negativo, limitado a `meta + min(horaExtra, |saldo|)` — só permite acumular hora extra suficiente pra zerar o débito, nunca ficar positivo. Flag `isLimitadoIndeferido` ignora a limitação; `preencheIntervencaoLimitado` cria a pendência de aprovação (efeito real ao deferir: `CalculoDiario.limitado = false`, campo sem equivalente no Frequencia hoje). **Regra individual por frequentador, não por regime — completamente nova, não documentada.**

### 4.5 Saída antecipada — trava mensal desativada (bug confirmado)
`PrimeiraEntradaUltimaSaidaV2` tem uma trava de "máx. 999 saídas antecipadas/mês" — mas a contagem real está **comentada no código** (`int qtdSaidasAntecipadasMensal = 0;` fixo). Na prática, a trava nunca bloqueia nada hoje. **Não replicar a trava tal como está — é código morto disfarçado de regra ativa.**

### 4.6 `isAusencia` — percentual mínimo de carga (distinto de falta)
`ausencia = true` quando `0 < trabalhado < meta * percentualCargaMinima / 100` (config por regime). Falta é `trabalhado == 0`; ausência é presença insuficiente. Não implementado no Frequencia.

### 4.7 Modalidade `OCORRENCIAS` com 2+ marcações — divergência real
Legado: 0 marcações → ausente; 1 marcação → presente com trabalhado = meta inteira (sem checar se bateu dentro do expediente — TODO explícito no código); **2+ marcações → calcula hora extra de verdade** (mesmo mecanismo de `EntradasESaidas`). O Frequencia (nota 16.3) só cobre os casos 0 e 1 marcação — **divergência de comportamento real quando um frequentador de modalidade OCORRENCIAS bate ponto mais de uma vez**.

### 4.8 Meta semanal de `OCORRENCIAS` calculada como `HORAS`
`Regime.metaSemanalInMilis()`: para modalidade `OCORRENCIAS`, delega pro cálculo de `HORAS` mesmo assim. Confirmar se o Frequencia replica isso ou calcula diferente.

### 4.9 `getMaxFaltasCompensadasPermitidasPorAno` — outra data de corte
12 faltas compensáveis/ano se `data > 26/10/2022`, senão 10. Mais uma constante de data hardcoded, distinta das datas GCET (2018-2022) e das 3 datas de nov/2022 já citadas.

### 4.10 Algoritmo completo de desconto de faltas em folha
`definirLabelsParaCalculosDiarios` (`CalculoDiarioServiceV2`): só roda para datas após 31/03/2017 e frequentador com biometria cadastrada (checagem de "livre de desconto" está **comentada/desativada** — roda pra todos hoje). Falta é compensada por saldo de banco de horas se `faltasCompensadas < maxPermitidasPorAno && saldoAcumuladoParcial - meta >= 0`; senão marca `faltaADescontar=true`, **limitado a 10 descontos por vez** (TODO do próprio autor questionando o hardcode: *"até quando vai existir esse limite??"*). **Exceção: estagiário não-extracurricular nunca tem falta marcada pra desconto.** Há também um bug conhecido documentado em comentário (`getSaldoBaseDesconto`): saldo inicial negativo + retificador positivo pode compensar falta indevidamente — a correção existe no código mas está **comentada/desativada**.

### 4.11 `BuscaPeriodosV2` — resolução de conflitos entre oneração/abono/feriado/direito
Algoritmo de subtração geométrica de intervalos de tempo para combinar período do regime + oneração + abono + feriado + direito. Relevante só se o Frequencia decidir implementar feriados/expediente excepcional no futuro — tem um branch redundante suspeito em `subtrair()` que vale revisão antes de portar.

### 4.12 `FIXME` confirmado: `temExpedienteExcepcional` sempre `false`
Comentário do próprio autor do legado (`CalculoStrategyV2.java:44`): *"fixme: nao funciona(aers) sempre retorna 'false'"*. O ramo inteiro de cálculo "com expediente excepcional" pode nunca executar de fato em produção. **Não replicar com prioridade alta sem confirmar em produção primeiro.**

---

## 5. Consolidação mensal, relatório final e jobs de recálculo

*(Ver Sprints 17-18 do SPRINT-PLAN para o que já está implementado — `RegistroMensalFrequencia`, `ConsolidacaoMensalService`, DUV-010/011 já corrigidos.)*

### 5.1 Dois jobs de recálculo com propósitos distintos (nenhum replicado fielmente)
- **`GerarRegistroMensalFrequencia`** (dia 2 de cada mês, 00:10): só **cria** `RegistroMensalFrequencia` se ainda não existir — nunca recalcula um mês já processado.
- **`RecalculoDiario`** (todo dia, 21:15): recalcula **o mês anterior inteiro**, incondicionalmente, todos os dias (correção tardia de marcações). O comentário do código menciona "mês atual" também, mas o código real só cobre o mês anterior — o comentário está desatualizado em relação ao comportamento real.
- **`CalcularFrequenciaJob`** (Frequencia, Sprint 17.5) tem filosofia diferente: recalcula últimos 3 dias + mês corrente, todo dia. É uma decisão de design consciente e razoável, mas não é o mesmo padrão do legado — o legado nunca recalcula o mês corrente automaticamente, só o anterior.
- **`CalculoDiarioAusentes`** (02:30 diário): critério de seleção via SQL bruto (dia aberto, ou sem registro, ou qualquer falta no mês) é amplo, mas **o corpo real do recálculo está comentado** — hoje o job só inativa frequentadores aposentados/vínculo encerrado, não recalcula nada de fato.

### 5.2 Fila assíncrona de recálculo (`HistoricoTarefa` / job `ExecutaTarefas`)
**Mecanismo estrutural inteiro não documentado em nenhuma sprint.** Tabela de fila (`presenca_historicotarefa`), job roda a cada 5min, despacha por `TipoEntidade`:
- `FERIADO` → recalcula o mês de todos afetados pela localização do feriado, só se já é retroativo;
- `DIAEXCEPCIONAL` → recalcula por órgão ou por frequentador, só dias já passados;
- `DIREITO` → recalcula os dias do período do direito;
- `VINCULAR_DESVINCULAR` → idem;
- `REGISTRO_FREQUENCIA`/`REGISTRO_ESTACAO` → recalcula o dia (se hoje) ou o mês;
- `RECALCULAR_TODOS` → força recálculo de todos os frequentadores com vínculo ativo.

Isso é o "trigger" real de recálculo em lote por mudança de feriado/direito/dia excepcional/vínculo — sem equivalente conhecido no Frequencia.

### 5.3 Auto-inativação de `APOSENTADO`
Job detecta frequentadores com categoria `APOSENTADO` no vínculo principal e inativa automaticamente (motivo fixo "Servidor Aposentado", data = início do vínculo).

---

## 6. Flags administrativas por dia (`CalculoDiario`) — 4 toggles manuais, todas exigindo role `PRESENCA_GERENCIA_FREQUENTADORES`

Nenhuma documentada em nota anterior. Todas exigem recálculo manual do mês depois de alteradas (a liberação não dispara recálculo automático) e são logadas para auditoria:

| Flag | Endpoint | Efeito |
|---|---|---|
| `liberadoBloqueioMaxHoraExtra` | `LiberarBloqueioMaxHoraExtra` | remove o cap de 2h/dia de banco de horas |
| `liberadoLimitacaoInicioHoraExtra` | `LiberarLimitacaoInicioHoraExtra` | remove a tolerância de 15min (seção 4.2) |
| `permitidoAcumularHoras` | `PermitirAcumularHoras` | permite saldo positivo de banco de horas naquele dia |
| `permitidoCompensarFalta` | `PermitirCompensarFaltas` | permite compensar falta por banco de horas naquele dia |
| `descontadoEmFolha` | `RetirarFaltaDescontadaEmFolha` | reverte "falta já descontada em folha" |

---

## 7. Achados críticos — comportamento "quebrado por design" no legado (não replicar sem decisão consciente)

1. **`temExpedienteExcepcional` sempre `false`** (seção 4.12) — FIXME do próprio autor.
2. **`CalculoDiarioAusentes` com corpo de recálculo comentado** — job "oficial" está desativado, só inativa vínculos.
3. **Trava de saída antecipada mensal desativada** (seção 4.5) — contagem real comentada, limite nunca aplicado.
4. **Teletrabalho COVID sob `if (false)`** — feature desligada permanentemente no código, mantida só por histórico/auditoria de Portaria.
5. **`configuraFalta` com bloco morto** — primeiro bloco de lógica granular é sobrescrito por um segundo bloco mais simples logo depois; o Frequencia já replica corretamente o comportamento *final* (segundo bloco).
6. **`VerificaComandos` com mensagem invertida** e **mecanismo de comandos remotos pra estação desativado por comentário** (`AdicioneEstacao`) — subsistema abandonado no meio do desenvolvimento.
7. **`ressalva` fixa em `false`** no processamento assíncrono de sincronização (`ProcessarArquivoSincronizado`) — comentário do autor indica intenção nunca implementada de marcar batidas offline como "ressalva".
8. **`DebitoRemanescenteNegociado` — código morto confirmado.** Nenhum DAO/Action/Service/JSP referencia essa classe em todo o código-fonte da Intranet. Confirma definitivamente a suspeita da task 22.2 do SPRINT-PLAN — seguro não replicar.

---

## 8. Regras operacionais de estação (EstacaoPonto) não documentadas

- **Status textual da estação** (`OK`/`ATENCAO`/`PROBLEMA`/`NUNCA`): baseado em dias desde o último contato (`0` dias = OK, `≤5` = ATENÇÃO, `>5` = PROBLEMA, nunca sincronizou = NUNCA) — distinto da lógica de `isAlive()`/heartbeat já descartada na Sprint 9.6.
- **Versionamento**: a estação sempre recebe a versão mais recente cadastrada (`ORDER BY releaseDate DESC`), decisão de atualizar fica 100% do lado do cliente desktop. Upload de nova versão exige 2 binários (X86/X64); mantém só as 5 versões mais recentes, apaga o resto fisicamente.
- **Sincronização de batidas é assíncrona em 2 fases**: gravação bruta imediata (`RegistroEstacaoPonto`, não processado) + job `ProcessarArquivoSincronizado` a cada 5min (só em horário comercial 7h-21h) que descriptografa, faz parse e cria `RegistroFrequencia` com checagem de idempotência por (frequentador, momento exato). Erro em um lote não impede os demais (transação por item).
- **Solicitação automática de autorização de prédio não permitido** pode ser disparada pelo próprio job de sincronização (não só manualmente) — é a origem real do mecanismo que a Sprint 19.4 do Frequencia implementou só como acionamento manual (decisão consciente, documentada, porque `Predio` não existe no Frequencia).
- **`PrediosPermitidos`**: a estação consulta seus prédios associados a cada inicialização — o impacto de não ter `Predio` no Frequencia vai além do processamento server-side.
- **`PontoDePresencaFilter`**: autenticação/autoprovisionamento de estação por `user-agent` contendo "JavaFX" + par (código único da máquina, código de ativação) — sem equivalente no Frequencia (canal diferente).
- **"Último" registro/ping é sempre por `id DESC`**, não por timestamp — relevante se algum dia houver inserção fora de ordem.
- **`ValidarFrequentador`** (login local pra batida manual na estação) exige `Frequentador.isPermitirManual() == true` — a checagem equivalente da estação (`isLiberadoBatidaManual`) está comentada/desativada no legado, só a do frequentador vale hoje.

---

## 9. Resumo de gaps priorizados para o backlog do Frequencia

Ordenado por impacto estimado (não por facilidade):

1. **Cascata de autorização de visualização/gestão de frequência** (seção 3) — a regra mais importante ainda sem equivalente no Frequencia. Sem ela, qualquer usuário autenticado com role "gestor" vê tudo (baseline atual da Sprint 23), não respeitando hierarquia de órgão nem `GestorIndividual`.
2. **11 roles granulares** (seção 2.3) vs. as 3 genéricas hoje no Frequencia (`admin`/`gestor`/`operador`) — decisão de produto: manter simplificado ou expandir.
3. **Fila de recálculo assíncrono por evento** (seção 5.2) — mecanismo estrutural que sustenta correção em cascata quando um feriado/direito/vínculo muda.
4. **Cap de banco de horas + as 4 flags administrativas por dia** (seções 4.3, 6) — decisão já adiada múltiplas vezes; este PRD tem agora o detalhe exato da fórmula (incluindo a janela GCET 2018-2022 e os 3 dias liberados em nov/2022) caso seja priorizado.
5. **Regra de compensação obrigatória do Ponto Facultativo por categoria** (seção 2, `isFrequentadorObrigadoACompensarHoras`) — só relevante se o Frequencia for tratar feriados/pontos facultativos.
6. **`isPermitidoModalidadeOcorrencias`** (seção 2.4) — 8 condições por título/lotação; precisa virar configuração, não hardcode, se replicado.
7. **`GestorIndividual` como fonte de autorização** (não só como cadastro visível) — hoje o Frequencia só tem a tela, não o uso na regra de acesso.
8. **Divergência real em modalidade `OCORRENCIAS`** (seção 4.7) — bug potencial de paridade: frequentadores dessa modalidade com 2+ marcações no dia recebem cálculo errado hoje (sempre trabalhado=meta, nunca considera hora extra).

---

## 10. Regras já confirmadas como corretamente implementadas (sem ação necessária)

- Vínculo `calculoDiario` do `RetificadorDeBancoHoras` nunca usado no legado — decisão de não portar (18.2) confirmada correta.
- `getSaldoMesAnterior` (cadeia recursiva mês a mês no legado) — equivalente funcional confirmado via campo `acumulado` persistido (17.1).
- `EstacaoPonto.isAtivo()` — regra replicada exatamente (9.6).
- Enums corretos em `deferirBaterPontoOutroPredio`/`indeferirBaterPontoOutroPredio` — bug de copy-paste do legado está isolado só na *criação* do pedido (`RegistroFrequencia`), não na resolução; a Sprint 19.4 já não replicou o bug.
- "Último" registro/ping por `id DESC` — mesmo critério provavelmente já usado no Frequencia via `created_at DESC` (confirmar).
- `getIpEnxuto()` com fallback `"0.0.0.0"` — regex de extração de IP já replicado (9.6); confirmar se o fallback também foi.

---

## Anexo — arquivos-fonte de referência

```
intranet/src/modules/presenca/beans/{Frequentador,Regime,RegimeFrequentador,ConfiguracaoFrequencia,GestorIndividual,CalculoDiario,RegistroMensalFrequencia,RetificadorDeBancoHoras,EstacaoPonto,RegistroEstacaoPonto}.java
intranet/src/modules/presenca/services/calculo/v2/{CalculoDiarioServiceV2,CalculoStrategyV2,PrimeiraEntradaUltimaSaidaV2,EntradasESaidasV2,OcorrenciasV2,BuscaPeriodosV2}.java
intranet/src/modules/presenca/services/RegistroFrequenciaServices.java
intranet/src/modules/presenca/services/RegimentoServices.java
intranet/src/modules/presenca/validators/RegistroFrequenciaValidator.java
intranet/src/modules/presenca/enums/{PresencaRolesEnum,PresencaProfilesEnum,TipoRegimeFrequentadorEnum}.java
intranet/src/modules/presenca/jobs/{CalculoDiarioAusentes,GerarRegistroMensalFrequencia,RecalculoDiario,ExecutaTarefas,ProcessarArquivoSincronizado,DiaExcepcionalCovid,DiaExcepcionalPontoFacultativo}.java
intranet/src/modules/presenca/actions/ajax/{LiberarBloqueioMaxHoraExtra,LiberarLimitacaoInicioHoraExtra,PermitirAcumularHoras,PermitirCompensarFaltas,RetirarFaltaDescontadaEmFolha,ValidarFrequentador}.java
intranet/web/init/suporte/presenca/{PONTO_FACULTATIVO,TRABALHO_REMOTO_COVID}.jsp
```
