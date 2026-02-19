# YOLO Architecture Diagrams

Visual reference for the YOLO engine architecture. All diagrams use Mermaid syntax for GitHub-native rendering.

Last Updated: 2026-02-19

---

## Diagram 1: Agent Hierarchy

```mermaid
graph TD
    subgraph Shared["Shared Department"]
        Owner["Owner<br/>(cross-dept review)"]
        Critic["Critic<br/>(gap analysis)"]
        Scout["Scout<br/>(research)"]
        Debugger["Debugger<br/>(incident response)"]
        IntGate["Integration Gate<br/>(cross-dept validation)"]
    end

    subgraph Backend["Backend Department"]
        BArch["Architect"]
        BLead["Lead"]
        BSenior["Senior"]
        BDev["Dev"]
        BTester["Tester"]
        BQA["QA<br/>(plan + code modes)"]
        BSecurity["Security"]
        BDoc["Documenter"]

        BDev --> BSenior
        BTester --> BSenior
        BSenior --> BLead
        BQA --> BLead
        BSecurity --> BLead
        BDoc --> BLead
        BLead --> BArch
    end

    subgraph Frontend["Frontend Department"]
        FArch["FE Architect"]
        FLead["FE Lead"]
        FSenior["FE Senior"]
        FDev["FE Dev"]
        FTester["FE Tester"]
        FQA["FE QA<br/>(plan + code modes)"]
        FSecurity["FE Security"]
        FDoc["FE Documenter"]

        FDev --> FSenior
        FTester --> FSenior
        FSenior --> FLead
        FQA --> FLead
        FSecurity --> FLead
        FDoc --> FLead
        FLead --> FArch
    end

    subgraph UIUX["UI/UX Department"]
        UArch["UX Architect"]
        ULead["UX Lead"]
        USenior["UX Senior"]
        UDev["UX Dev"]
        UTester["UX Tester"]
        UQA["UX QA<br/>(plan + code modes)"]
        USecurity["UX Security"]
        UDoc["UX Documenter"]

        UDev --> USenior
        UTester --> USenior
        USenior --> ULead
        UQA --> ULead
        USecurity --> ULead
        UDoc --> ULead
        ULead --> UArch
    end

    BArch --> Owner
    FArch --> Owner
    UArch --> Owner

    Critic -.->|"findings"| BLead
    Critic -.->|"findings"| FLead
    Critic -.->|"findings"| ULead
    Scout -.->|"research"| BLead
    Scout -.->|"research"| FLead
    Scout -.->|"research"| ULead

    Owner -->|"escalation"| User["User<br/>(via go.md)"]
```

**Source files:** `agents/yolo-*.md`, `references/company-hierarchy.md`, `references/departments/*.toon`

**Notes:**
- Solid arrows = escalation chain (Dev -> Senior -> Lead -> Architect -> Owner -> User)
- Dotted arrows = advisory (Critic/Scout findings flow to Leads)
- QA is a single agent with plan and code modes (merged from QA Lead + QA Code)
- Each department has 8 agents; Shared has 5 agents
- Single-dept mode uses Backend only; multi-dept adds Frontend and/or UI/UX via config

---
