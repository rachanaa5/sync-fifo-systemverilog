# Synchronous FIFO — SystemVerilog Design & Verification

A parameterized synchronous FIFO written in SystemVerilog, verified with a class-based layered testbench (generator, driver, monitor, scoreboard), SystemVerilog Assertions (SVA), and functional coverage.

## Features

**Design (`design.sv`)**
- Parameterized data width (`DATA_WIDTH`) and depth (`FIFO_DEPTH`)
- Single clock domain, active-low asynchronous reset
- Full/empty detection using an extra MSB on the read/write pointers
- Writes are ignored when full, reads are ignored when empty
- Registered read data (one-cycle read latency)
- Built-in SVA checks for overflow, underflow and reset state

**Testbench (`testbench.sv`)**
- `fifo_if` interface with clocking blocks and `DRV` / `MON` modports
- Constrained-random transaction item (`fifo_item`)
- Generator → Driver → DUT → Monitor → Scoreboard, connected by mailboxes
- Scoreboard with a queue-based golden model that accounts for the read latency
- Covergroup on `wr_en`, `rd_en`, `full`, `empty` and their crosses
- 500 randomized transactions per run, with a pass/fail and coverage summary
- Waveform dump to `dump.vcd`

## Repository structure

```
.
├── design.sv       # synchronous_fifo RTL + assertions
├── testbench.sv    # interface, class-based environment, top-level tb_fifo
└── README.md
```

## Parameters

| Parameter    | Default | Description                         |
|--------------|---------|-------------------------------------|
| `DATA_WIDTH` | 8       | Width of each data word, in bits    |
| `FIFO_DEPTH` | 16      | Number of entries (power of two)    |

## Ports

| Port      | Direction | Width        | Description                         |
|-----------|-----------|--------------|-------------------------------------|
| `clk`     | input     | 1            | Clock                               |
| `rst_n`   | input     | 1            | Active-low asynchronous reset       |
| `wr_en`   | input     | 1            | Write enable                        |
| `rd_en`   | input     | 1            | Read enable                         |
| `wr_data` | input     | `DATA_WIDTH` | Data to write                       |
| `rd_data` | output    | `DATA_WIDTH` | Data read (valid the cycle after a read) |
| `full`    | output    | 1            | FIFO is full                        |
| `empty`   | output    | 1            | FIFO is empty                       |

## Running the simulation

### Synopsys VCS

```bash
vcs -sverilog -full64 -timescale=1ns/1ps -debug_access+all -cm line+cond+fsm+tgl+assert \
    design.sv testbench.sv -o simv
./simv -cm line+cond+fsm+tgl+assert
```

### EDA Playground

1. Paste `design.sv` into the **Design** pane and `testbench.sv` into the **Testbench** pane.
2. Select a SystemVerilog simulator that supports classes and covergroups (e.g. Synopsys VCS or Cadence Xcelium).
3. Enable **Open EPWave after run** to view the waveform.

### Expected output

```
==============================================
SIMULATION COMPLETED
Scoreboard Results: 264 PASSED, 0 FAILED
Functional Coverage: 100%
==============================================
```

Because the stimulus is fully random, the testbench will sometimes assert `wr_en` while the FIFO is full or `rd_en` while it is empty. The DUT safely ignores these requests, but the overflow/underflow assertions will report them as `[SVA ERROR]` / `[IF SVA ERROR]` messages. Those messages show the assertions working; they do not mean the data is wrong. Scoreboard failures do.

## License

Add a license of your choice (for example, MIT) before publishing.
