// =====================================================================
//  tb_stm.v  -  stm_sys のテストベンチ
//    C シミュレータ (soft/chc で作る stmsiml) と同じ手順で動かす:
//      * メモリを初期化して PC=開始番地から実行
//      * 各サイクル, Mem[PC>>2] の上位 4bit が 0xD (診断命令 DD/DF...) なら終了
//      * bup0/bup1 のテストは SUCCESS (0x3F0) で終われば OK, DEAD (0x3D0) は NG
//
//  plusargs:
//    +HEX=<file>      $readmemh 形式のメモリイメージ (tools/mem2hex.py で作る)
//    +PC=<hex>        開始番地
//    +CYCLES=<dec>    最大サイクル数
//    +RANDOM          キャッシュミスを乱数で模擬 (C 版の 'stmsiml -r')
//    +SEED=<dec>      乱数の種
//    +TRACE           毎サイクル PC 等を表示
//    +CTRACE          C シミュレータの siml.res と同じ形式で毎サイクル出力
//
//  コンソール (Verilog 版で追加): 番地 F000_0008 に語をストアすると, その下位 8bit を
//  1 文字として表示する ($write)。tb_stm_axi.v (axi4_mem_slave) と同じ番地。
//  stm_memory は番地の下位 12bit しか見ないので, メモリの 0x008 にも書かれる。
//
//  tb_stm.v  -  testbench for stm_sys
//    Runs the same way as the C simulator (stmsiml, built with soft/chc):
//      * initialise the memory and run from PC = start address
//      * stop when the top 4 bits of Mem[PC>>2] are 0xD (diagnostic instructions DD/DF...) in a cycle
//      * the bup0/bup1 tests pass if they end at SUCCESS (0x3F0); DEAD (0x3D0) is a failure
//
//  plusargs:
//    +HEX=<file>      memory image in $readmemh format (made by tools/mem2hex.py)
//    +PC=<hex>        start address
//    +CYCLES=<dec>    maximum number of cycles
//    +RANDOM          simulate cache misses at random ('stmsiml -r' of the C version)
//    +SEED=<dec>      random seed
//    +TRACE           print PC etc. every cycle
//    +CTRACE          print every cycle in the same format as siml.res of the C simulator
//
//  Console (added in the Verilog version): storing a word to address F000_0008 prints its low
//  8 bits as a character ($write). The same address as tb_stm_axi.v (axi4_mem_slave).
//  stm_memory only looks at the low 12 address bits, so it is also written to 0x008 of the memory.
//
// 【解説】テストベンチの構成とネット
//   ・tb_stm と stm_sys の間のネットは、入力の clk, rst, reset_pc, rnd_opclh /
//     rnd_ifrdy / rnd_ifclh と、出力の pc だけ。
//     stm_sys の中のレジスタファイルとメモリの配線は stm_sys.v を参照。
//   ・回路の中の信号は、階層名 (u_sys.u_cntl.D_FWD など) で直接のぞいている。
//     ネットリストに 1 対 1 に対応する名前 (stm_cntl の中の wire / reg) なので、
//     C シミュレータの出力 (siml.res) と同じ信号をサイクルごとに比べられる。
//   ・テストベンチ自身は論理合成しない (initial, $readmemh, $random, #遅延 を使う)。
//   ・時間の流れ: クロック周期 10 (#5 で反転)。乱数入力は立ち下がりで変え、
//     #1 待ってから表示するので、表示する値は「次の立ち上がりで FF に入る直前」
//     = そのサイクルの組合せ回路が落ち着いた値。
//
// [Note] Structure of the testbench and its nets
//   - The nets between tb_stm and stm_sys are only the inputs clk, rst, reset_pc, rnd_opclh /
//     rnd_ifrdy / rnd_ifclh and the output pc.
//     For the wiring of the register file and memory inside stm_sys, see stm_sys.v.
//   - Signals inside the circuit are looked at directly by hierarchical names (u_sys.u_cntl.D_FWD etc.).
//     These names map one to one onto the netlist (wires / regs inside stm_cntl), so the same
//     signals as the output of the C simulator (siml.res) can be compared cycle by cycle.
//   - The testbench itself is not synthesized (it uses initial, $readmemh, $random, # delays).
//   - Timing: the clock period is 10 (toggles every #5). The random inputs change on the falling
//     edge, and values are printed after waiting #1, so what is printed is "just before it goes
//     into the FFs on the next rising edge" = the settled value of the cycle's combinational logic.
// =====================================================================
module tb_stm;                                          // テストベンチ (ポート無し, シミュレーション専用で合成されない) / testbench (no ports, simulation only, never synthesized)
  reg         clk = 1'b0;                               // クロック (初期値0のreg, 下のalwaysで反転) / clock (reg starting at 0, toggled below)
  reg         rst = 1'b1;                               // リセット: 1で始める / reset: starts at 1
  reg  [31:0] reset_pc;                                 // 開始番地 (+PC=で指定) / start address (from +PC=)
  reg         rnd_opclh = 1'b1, rnd_ifrdy = 1'b1, rnd_ifclh = 1'b1; // キャッシュミス模擬の3入力: 既定は常時1 (ミス無し) / the 3 cache-miss inputs: default always 1 (no misses)
  wire [31:0] pc;                                       // DUTのPC (停止判定用) / the DUT's PC (to detect the stop)

  reg  [8*1024-1:0] hexfile;     // +HEX= のファイル名 (最大 1024 文字)
                                 // file name from +HEX= (up to 1024 characters)
  integer       cycles, maxcyc, seed;                   // サイクル数, 上限, 乱数の種 / cycle count, limit, random seed
  reg           use_random, trace, ctrace;              // +RANDOM / +TRACE / +CTRACE の有無 / presence of +RANDOM / +TRACE / +CTRACE
  reg  [31:0]   insn;                                   // PCの位置の命令語 (停止判定) / instruction word at PC (stop check)

  stm_sys u_sys (                                       // 被試験回路 (DUT): CPU+レジスタファイル+メモリ / device under test: CPU + register file + memory
    .clk              (clk),                            // クロック / clock
    .rst              (rst),                            // リセット / reset
    .RESET_PC         (reset_pc),                       // 開始番地 / start address
    .RANDOM_FOR_OPCLH (rnd_opclh),                      // オペランドのヒット (乱数) / operand hit (random)
    .RANDOM_FOR_IFRDY (rnd_ifrdy),                      // フェッチ受け付け (乱数) / fetch ready (random)
    .RANDOM_FOR_IFCLH (rnd_ifclh),                      // フェッチ到着 (乱数) / fetch arrival (random)
    .PC               (pc)                              // PCを観測 / observe PC
  );                                                    // u_sysの終わり / end of u_sys

  always #5 clk = ~clk;                                 // 5単位ごとに反転 = 周期10のクロック / toggle every 5 units = clock period 10

  // コンソール: F000_0008 へのストアで 1 文字表示
  // console: a store to F000_0008 prints one character
  always @(posedge clk)                                 // 毎クロック, メモリへのストアを見張る / watch memory stores every clock
    if (!rst && u_sys.u_mem.we && u_sys.u_mem.opad == 32'hf000_0008) // F000_0008へのストアなら (階層参照: 合成後のネットリストには無い名前) ... / a store to F000_0008 (hierarchical reference: no such name in a netlist) ...
      $write("%c", u_sys.u_mem.stdt[7:0]);              // ...下位8bitを1文字として表示 / ... print the low 8 bits as a character

  initial begin                                         // テストの手順 (時間の流れに沿って1回だけ実行) / the test sequence (runs once along simulated time)
    if (!$value$plusargs("HEX=%s", hexfile)) begin      // +HEX=が無ければ使い方を表示して終わる / no +HEX=: print usage and quit
      $display("usage: vvp sim +HEX=mem.hex +PC=300 +CYCLES=250 [+RANDOM] [+SEED=n]"); // 使い方 / usage
      $finish;                                          // シミュレーション終了 / end the simulation
    end                                                 // if の終わり / end of if
    if (!$value$plusargs("PC=%h", reset_pc))   reset_pc = 32'h300; // 開始番地 (既定0x300) / start address (default 0x300)
    if (!$value$plusargs("CYCLES=%d", maxcyc)) maxcyc   = 250; // サイクルの上限 (既定250) / cycle limit (default 250)
    if (!$value$plusargs("SEED=%d", seed))     seed     = 1; // 乱数の種 (既定1) / random seed (default 1)
    use_random = $test$plusargs("RANDOM");              // キャッシュミス模擬を使うか / use the miss simulation?
    trace      = $test$plusargs("TRACE");               // 毎サイクルの状態表示 / per-cycle trace
    ctrace     = $test$plusargs("CTRACE");              // C版と比べる形式の表示 / trace in the C-version comparison format

    $readmemh(hexfile, u_sys.u_mem.mem);                // プログラムをメモリの配列へ直接読み込む / load the program straight into the memory array

    repeat (2) @(posedge clk);                          // リセットを2クロック (同期リセットなのでクロックが要る) / hold reset 2 clocks (a sync reset needs clocks)
    @(negedge clk) rst = 1'b0;                          // 立ち下がりでリセット解除 (立ち上がりとの競合を避ける) / release reset on the falling edge (avoid races with the rising edge)

    for (cycles = 1; cycles <= maxcyc; cycles = cycles + 1) begin // 1サイクルずつ進める / step one cycle at a time
      // 立ち下がりで乱数入力を更新 (C 版は 1 サイクルごとに random())
      // update the random inputs on the falling edge (the C version calls random() once per cycle)
      if (use_random) begin                             // 乱数モードなら / in random mode
        rnd_opclh = (($random(seed) & 15) >= 8);        // 1/2の確率でヒット (C版と同じ式) / hit with probability 1/2 (same formula as C)
        rnd_ifrdy = (($random(seed) & 15) >= 8);        // 1/2の確率で受け付け / ready with probability 1/2
        rnd_ifclh = (($random(seed) & 15) >= 8);        // 1/2の確率で到着 / arrives with probability 1/2
      end                                               // if の終わり / end of if
      #1;                                               // 組合せ回路が落ち着くのを待つ / let the combinational logic settle
      // 【解説】PC は「完了した命令の次の番地」(080_w_act.vh)。その番地の命令が
      //         診断命令 (上位 4bit = 0xD) なら、テストプログラムの終わりに着いた。
      // [Note] PC is "the address after the completed instructions" (080_w_act.vh). If the instruction at that
      //        address is a diagnostic instruction (top 4 bits = 0xD), the test program has reached its end.
      insn = u_sys.u_mem.mem[pc[11:2]];                 // PCの位置の命令語をメモリから直接読む / read the insn at PC straight from memory
      if (trace)                                        // +TRACEなら / with +TRACE
        $display("%4d PC=%h D_FWD=%b A_FWD=%b B_FWD=%b E_FWD=%b W_COMPLETE=%b I0=%h I1=%h", // 各ステージが進んだか等を表示 / show which stages moved etc.
                 cycles, pc, u_sys.u_cntl.D_FWD, u_sys.u_cntl.A_FWD, // 表示する値: サイクル, PC, D/A段のFWD (内部ネットの階層参照) / values: cycle, PC, D/A FWD (hierarchical refs to internal nets)
                 u_sys.u_cntl.B_FWD, u_sys.u_cntl.E_FWD, // B/E段のFWD / B/E FWD
                 u_sys.u_cntl.W_COMPLETE, u_sys.u_cntl.I0, u_sys.u_cntl.I1); // 完了と発行候補の命令 / completion and the issue candidates
      if (ctrace)   // C 版 siml.res と同じ並び (比較用 form.dat: tools/form_cmp.dat)
                    // same order as siml.res of the C version (form.dat for comparison: tools/form_cmp.dat)
        $display("%h%h%h%h%h%h%h%h%h%h%h%h%h%h%h",      // C版siml.resと同じ並びで16進表示 / hex dump in the order of the C version's siml.res
                 pc, u_sys.u_cntl.D_FWD, u_sys.u_cntl.A_FWD, u_sys.u_cntl.B_FWD, // PCと各段のFWD / PC and stage FWDs
                 u_sys.u_cntl.E_FWD, u_sys.u_cntl.W_COMPLETE, // E段とW / E stage and W
                 u_sys.u_cntl.I0, u_sys.u_cntl.I1, u_sys.u_cntl.IB_AD, // 発行候補とフェッチ番地 / issue candidates and fetch address
                 u_sys.u_cntl.LBS_AD, u_sys.u_cntl.W_WDT1, u_sys.u_cntl.W_WDT2, // オペランド番地とWの書き込みデータ / operand address and W write data
                 u_sys.u_cntl.PSW_CC, u_sys.u_cntl.NIP_A, u_sys.u_cntl.NIP_B); // CCと両キューのNIP / CC and the NIPs of both queues
      if (insn[31:28] == 4'hD) begin                    // 診断命令 (0xD...) に着いたら止める / stop on a diagnostic insn (0xD...)
        if (pc == 32'h3f0)                              // 0x3f0 = テスト成功の印 / 0x3f0 = test passed
          $display("RESULT: stop at PC=%h after %0d cycles -> OK", pc, cycles); // 成功を表示 (run_bup.shがこの行を見る) / report success (run_bup.sh greps this)
        else if (pc == 32'h3d0)                         // 0x3d0 = テスト失敗の印 / 0x3d0 = test failed
          $display("RESULT: stop at PC=%h after %0d cycles -> DEAD", pc, cycles); // 失敗を表示 / report failure
        else                                            // それ以外の番地で止まった / stopped elsewhere
          $display("RESULT: stop at PC=%h after %0d cycles -> STOP", pc, cycles); // 停止を表示 / report a plain stop
        $finish;                                        // 終了 / finish
      end                                               // if の終わり / end of if
      @(negedge clk);                                   // 次の立ち下がりまで進める (1サイクル) / advance to the next falling edge (one cycle)
    end                                                 // for の終わり / end of for
    $display("RESULT: timeout PC=%h after %0d cycles -> TIMEOUT", pc, maxcyc); // 上限まで止まらなかった / did not stop within the limit
    $finish;                                            // 終了 / finish
  end                                                   // initial の終わり / end of initial
endmodule                                               // モジュールの終わり / end of module
