# Documentação de Conhecimento — Migração do Módulo Frequência

> **Este diretório é a fonte central consolidada de todo o conhecimento gerado** durante a migração do módulo de Frequência da Intranet (legado) para o novo sistema Frequência.
>
> **Fonte de verdade** para navegação do time e **ponto de entrada** para apresentação/consulta da documentação.

---

## ✅ Estado Atual do Projeto (2026-08-05)

| Fase | Status | Onde |
|------|--------|------|
| **Fase 1 — Inventário do legado** | ✅ **CONCLUÍDO** (domínios + DUVs + **schema físico coletado do MySQL**) | `01-inventario/` |
| **Fase 2 — Engenharia Reversa (Fluxos A–D)** | ✅ **CONCLUÍDA** | `09-intranet/fluxos/` |
| **Fase 3 — Mapeamento de Domínio (DDD)** | ✅ **CONCLUÍDA** | `03-dominio/` |
| **Fases 4+ (ARQUITETURA / CÓDIGO)** | ⏸️ **SUSPENSAS** por decisão do usuário | `02-arquitetura/` |
| **PRD + Plano (Sprints/Tasks)** | 🔜 Próximo passo (após inventário fechado) | — |

> **Fluxo definido pelo usuário:** Inventário ✅ → **PRD** → **Plano de Desenvolvimento (Sprints + Tasks)** → só então Fase 4 (arquitetura/código Rails).

---

## 📋 Visão Rápida das Fases (0–9)

| Fase | Entregável principal | Status |
|------|----------------------|--------|
| **0** | Preparação / estrutura do projeto OpenCode | ✅ Feita |
| **1** | Inventário completo do legado (domínios, tabelas, schema) | ✅ Concluída |
| **2** | Engenharia Reversa (fluxos A–D, regras com evidência) | ✅ Concluída |
| **3** | Mapeamento de Domínio / DDD (bounded contexts, agregados, eventos, casos de uso) | ✅ Concluída |
| **4** | Arquitetura Alvo (Rails + DDD) | ⏸️ Suspensa (após PRD) |
| **5** | Estratégia de Migração (Strangler Fig) | 🔜 Pendente |
| **6** | Plano de Compatibilidade (EstaçãoPonto) | 🔜 Pendente |
| **7** | Plano de Implementação (Sprints/Tasks) | 🔜 Pendente (PRD antes) |
| **8** | Plano de Testes | 🔜 Pendente |
| **9** | Plano de Implantação | 🔜 Pendente |

---

## 📁 Índice por Pasta (navegação)

| Pasta | Fase | Conteúdo | Índice |
|-------|------|----------|--------|
| `00-contexto/` | Base | Visão geral, framework de 10 fases, convenções | [`00-visao-geral.md`](00-contexto/00-visao-geral.md) · [`01-framework-migracao.md`](00-contexto/01-framework-migracao.md) · [`02-convencoes.md`](00-contexto/02-convencoes.md) |
| `01-inventario/` | **Fase 1** | **Inventário completo do legado** (domínios, tabelas, schema) | [`00-indice.md`](01-inventario/00-indice.md) |
| `03-dominio/` | **Fase 3** | **Mapeamento de Domínio (DDD)** | [`00-indice.md`](03-dominio/00-indice.md) |
| `04-decisoes/` | Análises/Decisões | Análises técnicas e decisões (ex.: TLC Spec-Driven) | [`tlc-spec-driven-integration.md`](04-decisoes/tlc-spec-driven-integration.md) |
| `05-migracao/` | **Fase 5** | Estratégia de migração, PoC `api-ponto/` | [`00-codigo-preexistente-poc.md`](05-migracao/00-codigo-preexistente-poc.md) |
| `06-integracoes/` | Integrações | Integrações entre sistemas (digitais, contratos) | [`00-indice.md`](06-integracoes/00-indice.md) |
| `07-estacao-ponto/` | **Fase 6** | **EstaçãoPonto** (arquitetura, endpoints, compat DES) | [`00-indice.md`](07-estacao-ponto/00-indice.md) |
| `08-pessoas/` | Integrações | **Pessoas** (fonte de dados cadastrais, ADR-0001) | [`00-indice.md`](08-pessoas/00-indice.md) |
| `09-intranet/` | **Fases 1–2** | **Intranet legada** — módulo `presenca`, fluxos A–D, DUVs | [`00-indice-modulo-presenca.md`](09-intranet/00-indice-modulo-presenca.md) |
| `02-arquitetura/` | **Fase 4** | Arquitetura do novo sistema — **a preencher** (após PRD) | *(vazia)* |
| `10-testes/` / `11-deploy/` | **Fases 8/9** | Testes e implantação — a preencher | *(vazias)* |
| `adr/` | Decisões | Architecture Decision Records | [ADRs `0000`–`0009`](adr/) |
| `specs/` | — | Memória/estado da sessão (Spec-Driven) | `STATE.md` |
| `duvidas/` | — | Rastreamento de dúvidas (resolvidas e realocadas) | `README.md` |

---

# 📌 Relatórios por Fase

## Fase 1 — Inventário do Legado ✅ CONCLUÍDA

**Entregáveis** (`01-inventario/`):
- **4 domínios de negócio** documentados (`02`–`05`): Regime/Jornada, Cálculo Diário, Direitos/Afastamentos, Banco de Horas/Fechamento.
- **13 dúvidas técnicas (DUV-001..013) resolvidas** e realocadas por tema (`08-pessoas/`, `07-estacao-ponto/`, `09-intranet/`).
- **19 tabelas + 3 de junção inventariadas** e **schema físico coletado do MySQL** (banco `intranet`) — tipos, índices e FKs reais em [`01-inventario/09-schema-confirmado.md`](01-inventario/09-schema-confirmado.md).
- **Coexistência de 2 motores de cálculo (v1 e v2)** identificada — risco de divergência de resultados.
- **Integração de digitais** EstaçãoPonto ⇄ Intranet mapeada (`06-integracoes/00-digitais-estacao-intranet.md`).

> 📌 **Detalhe de dados:** a estrutura do banco foi coletada de base local (`intranet`, MariaDB 10.4.32). A **estrutura é autêntica**, mas os **dados são de teste/amostra** — recomenda-se validar com a equipe de dados a estrutura de produção e a **view `presenca_frequentadorestacao`** (ausente na base local).

**Índice completo:** [`01-inventario/00-indice.md`](01-inventario/00-indice.md)

---

## Fase 2 — Engenharia Reversa ✅ CONCLUÍDA

**Entregáveis** (`09-intranet/fluxos/`) — 4 fluxos principais diagramados com regras e **evidência `arquivo:linha`**:

| # | Fluxo | Doc | Conteúdo |
|---|-------|-----|----------|
| A | Batida de Ponto | [`01-batida-ponto.md`](09-intranet/fluxos/01-batida-ponto.md) | Ingestão EP-05 + processamento assíncrono + regras R1–R6 + pendências |
| B | Cálculo Diário | [`02-calculo-diario.md`](09-intranet/fluxos/02-calculo-diario.md) | Motores v1/v2 + disparos T1–T4 + regras C1–C9 + cortes temporais |
| C | Fechamento | [`03-fechamento.md`](09-intranet/fluxos/03-fechamento.md) | Mensal (`RegistroMensalFrequencia`) + definitivo (`RelatorioFrequenciaFinal`) + retificador/retroativo |
| D | Gerenciamento de Registro | [`04-gerenciamento-registro.md`](09-intranet/fluxos/04-gerenciamento-registro.md) | Manual/errata, desconsiderar/reconsiderar, autorizações |

**Índice do módulo:** [`09-intranet/00-indice-modulo-presenca.md`](09-intranet/00-indice-modulo-presenca.md)

---

## Fase 3 — Mapeamento de Domínio (DDD) ✅ CONCLUÍDA

**Entregáveis** (`03-dominio/`) — 07 documentos a partir dos fluxos da Fase 2:

| # | Documento | Conteúdo |
|---|-----------|----------|
| 01 | [`01-linguagem-ubiqua.md`](03-dominio/01-linguagem-ubiqua.md) | Glossário do domínio + termos a evitar (antecorrupção) |
| 02 | [`02-bounded-contexts.md`](03-dominio/02-bounded-contexts.md) | PESSOAS / FREQUÊNCIA / ESTAÇÃO PONTO + ACL |
| 03 | [`03-agregados.md`](03-dominio/03-agregados.md) | Agregados AG-1..AG-7 (`Dia` = raiz do cálculo) |
| 04 | [`04-entidades-value-objects.md`](03-dominio/04-entidades-value-objects.md) | Entidades e Value Objects |
| 05 | [`05-eventos-dominio.md`](03-dominio/05-eventos-dominio.md) | Eventos de domínio E1–E11 + P1–P3 |
| 06 | [`06-servicos-dominio.md`](03-dominio/06-servicos-dominio.md) | Serviços de domínio |
| 07 | [`07-casos-uso.md`](03-dominio/07-casos-uso.md) | Casos de uso UC-01..UC-18 priorizados |

**Índice completo:** [`03-dominio/00-indice.md`](03-dominio/00-indice.md)

---

## Fase 4 — Arquitetura Alvo ⏸️ SUSPENSA (após PRD)

Este é o **próximo bloco de trabalho após o PRD** (decisão do usuário: **não construir antes**). Quando iniciada, cobrirá (`02-arquitetura/`):
- Diagrama de camadas (Controllers, Services, Models, Domain, Infrastructure) — Rails API-only
- Definição de API (endpoints, formato, versionamento)
- Estratégia de autenticação/autorização
- Integração com **Pessoas** (API REST + Eventos) e com **EstaçãoPonto** (camada de compatibilidade)
- Definição de jobs, filas e processamento assíncrono
- ADRs das decisões arquiteturais

> A Fase 4 depende diretamente do entendimento sólido de domínio (Fase 3) e do PRD, que está em **próximo passo** na fila do usuário.

---

## Fases 5–9 🔜 PENDENTES

| Fase | Conteúdo | Onde (quando iniciada) |
|------|----------|------------------------|
| **5 — Estratégia de Migração** | Strangler Fig com proxy reverso; estratégia já recomendada no framework | `05-migracao/` |
| **6 — Compatibilidade EstaçãoPonto** | Adaptador / proxy / replicação de API; mínimo de alteração na estação | `07-estacao-ponto/` / `06-integracoes/` |
| **7 — Plano de Implementação** | Sprints e Tasks (a partir do **PRD**) | — |
| **8 — Plano de Testes** | RSpec, integração, contrato (Pact), regressão, homologação | `10-testes/` |
| **9 — Plano de Implantação** | CI/CD, rollback, monitoramento, observabilidade | `11-deploy/` |

---

## Convenções de Uso

- As **dúvidas** (🤔 DÚVIDA) são registradas em `duvidas/` com ID `DUV-NNN`; quando resolvidas, são **realocadas para a pasta temática** e o `duvidas/README.md` mantém o rastreamento do novo local.
- Decisões arquiteturais são registradas como **ADR** (ver `adr/0000-template.md`).
- Cada pasta numerada corresponde a uma fase/grupo de conhecimento do framework (ver `00-contexto/01-framework-migracao.md`).
- Os **fluxos de engenharia reversa** (Fase 2) ficam em `09-intranet/fluxos/` com evidência `arquivo:linha`.

---
**Última atualização:** 2026-08-05
