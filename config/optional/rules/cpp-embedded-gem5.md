---
trigger: model_decision
description: Rules for C, C++, bare-metal ARM Cortex-M3 firmware, RISC-V assembly, and gem5 architectural simulation projects.
---
# C/C++, Embedded & gem5 Rules
1. Verify that `compile_commands.json` exists (`cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) and always compile with `-Wall -Wextra`.
2. **ARM Cortex-M3**: Use `volatile` for all MMIO registers and variables shared with ISRs; never call `malloc`/`new` inside ISRs; check SRAM/Flash usage with `arm-none-eabi-size`.
3. **RISC-V & gem5**: Respect the RISC-V ABI (16-byte stack alignment). Extract metrics from `m5out/stats.txt` via `rg` instead of loading the full file into context.
