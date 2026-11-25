// =====================================================================
//  tb_exp.v  -  tb_stm.v の実験用の古いコピー
//    tb/tb_stm.v との違いは 2 つだけ:
//      * +RANDOM のとき乱すのは RANDOM_FOR_OPCLH (オペランドのキャッシュミス) だけで,
//        ミスの率は 1/2 ではなく 3/4 ((乱数 & 15) >= 12 のときだけヒット)。
//        RANDOM_FOR_IFRDY / RANDOM_FOR_IFCLH (命令フェッチ) は常に 1 = いつもヒット。
//        ロード / ストア側のインターロックだけを強く揺さぶるための設定。
//      * コンソール (F000_0008 へのストアで 1 文字表示) がまだ無い。
//    モジュール名は tb_stm のままなので, tb/tb_stm.v とは同時にコンパイルできない。
//    使い方 (tb/tb_stm.v の代わりに指定する):
//      iverilog -g2001 -I rtl -o exp.vvp tb/tb_exp.v rtl/stm_sys.v rtl/stm_cntl.v \n//               rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
//
//  tb_exp.v  -  old experimental copy of tb_stm.v
//    Only 2 differences from tb/tb_stm.v:
//      * with +RANDOM only RANDOM_FOR_OPCLH (operand cache misses) is randomised, and the miss
//        rate is 3/4 instead of 1/2 (a hit only when (random & 15) >= 12).
//        RANDOM_FOR_IFRDY / RANDOM_FOR_IFCLH (instruction fetch) are always 1 = always hit.
//        A setting that shakes only the load / store side interlocks hard.
//      * the console (a store to F000_0008 prints one character) is not there yet.
//    The module name stays tb_stm, so it cannot be compiled together with tb/tb_stm.v.
//    Usage (give it instead of tb/tb_stm.v):
//      iverilog -g2001 -I rtl -o exp.vvp tb/tb_exp.v rtl/stm_sys.v rtl/stm_cntl.v \n//               rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
//
//  (以下は元の tb_stm.v の説明 / below is the original description of tb_stm.v)
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
// 【ネットリスト解説】テストベンチの構成とネット
//   ・tb_stm と stm_sys の間のネットは, 入力の clk, rst, reset_pc, rnd_opclh /
//     rnd_ifrdy / rnd_ifclh と, 出力の pc だけ (stm_sys の中の配線は stm_sys.v を参照)。
//   ・rnd_* は stm_cntl の RANDOM_FOR_* 入力で, 元の C 版で「キャッシュのデータが
//     揃った」を表す信号。stm_sys ではメモリ (stm_memory) が組合せで読めるので,
//     本当はいつでも揃っている。それを 0 にすると, 回路は「データが来ない」と見て
//     E_LMD_INTLK (070) などのインターロックでパイプラインを止める。
//     rnd_opclh は 050 の B_OPCLH (OR の 1 入力) に, rnd_ifclh は 180 の SU_IF_CLH に入る。
//   ・回路の中の信号は階層名 (u_sys.u_cntl.D_FWD など) で直接のぞいている。
//     RTL の wire / reg の名前なので, C シミュレータの出力 (siml.res) と同じ信号を
//     サイクルごとに比べられる。合成後のネットリストでは, 組合せの wire (D_FWD など) は
//     LUT に吸収されて名前が残らないことが多い。
//   ・テストベンチ自身は論理合成しない (initial, $readmemh, $random, #遅延 を使う)。
//   ・時間の流れ: クロック周期 10 (#5 で反転)。乱数入力は立ち下がりで変え,
//     #1 待ってから表示するので, 表示する値は「次の立ち上がりで FF に入る直前」
//     = そのサイクルの組合せ回路が落ち着いた値。
//
// [Netlist notes] Structure of the testbench and its nets
//   - The nets between tb_stm and stm_sys are only the inputs clk, rst, reset_pc, rnd_opclh /
//     rnd_ifrdy / rnd_ifclh and the output pc (for the wiring inside stm_sys see stm_sys.v).
//   - rnd_* are the RANDOM_FOR_* inputs of stm_cntl, the signals meaning "the cache data is
//     ready" in the original C version. In stm_sys the memory (stm_memory) is read
//     combinationally, so the data is really always ready. Driving them to 0 makes the circuit
//     see "no data" and stall the pipeline with interlocks such as E_LMD_INTLK (070).
//     rnd_opclh goes to B_OPCLH of 050 (one input of an OR), rnd_ifclh to SU_IF_CLH of 180.
//   - Signals inside the circuit are looked at directly by hierarchical names
//     (u_sys.u_cntl.D_FWD etc.). These are RTL wire / reg names, so the same signals as the
//     output of the C simulator (siml.res) can be compared cycle by cycle. In the synthesized
//     netlist, combinational wires (D_FWD etc.) are usually absorbed into LUTs and their names disappear.
//   - The testbench itself is not synthesized (it uses initial, $readmemh, $random, # delays).
//   - Timing: the clock period is 10 (toggles every #5). The random inputs change on the falling
//     edge, and values are printed after waiting #1, so what is printed is "just before it goes
//     into the FFs on the next rising edge" = the settled value of the cycle's combinational logic.
// =====================================================================
module tb_stm;
  reg         clk = 1'b0;                // クロック (always #5 で反転, 周期 10)
                                         // clock (toggled by always #5, period 10)
  reg         rst = 1'b1;                // 同期リセット (1 でリセット中)
                                         // synchronous reset (1 = in reset)
  reg  [31:0] reset_pc;                  // リセット後に実行を始める番地 (+PC=)
                                         // address where execution starts after reset (+PC=)
  reg         rnd_opclh = 1'b1, rnd_ifrdy = 1'b1, rnd_ifclh = 1'b1;
                                         // キャッシュのデータが揃った (0 でミスを模擬)
                                         // cache data ready (0 simulates a miss)
  wire [31:0] pc;                        // 完了した命令の次の番地 (080_w_act.vh)
                                         // address after the completed instructions (080_w_act.vh)

  reg  [8*1024-1:0] hexfile;     // +HEX= のファイル名 (最大 1024 文字)
                                 // file name from +HEX= (up to 1024 characters)
  integer       cycles, maxcyc, seed;    // 今のサイクル, 最大サイクル数, 乱数の種
                                         // current cycle, maximum cycles, random seed
  reg           use_random, trace, ctrace;   // +RANDOM / +TRACE / +CTRACE が付いたか
                                             // whether +RANDOM / +TRACE / +CTRACE was given
  reg  [31:0]   insn;                    // PC の番地にある命令 (終了判定用)
                                         // the instruction at PC (for the stop check)

  // 【解説】DUT。stm_sys は stm_cntl + stm_regfile + stm_memory をつないだもの。
  // [Note] The DUT. stm_sys connects stm_cntl + stm_regfile + stm_memory.
  stm_sys u_sys (
    .clk              (clk),
    .rst              (rst),
    .RESET_PC         (reset_pc),
    .RANDOM_FOR_OPCLH (rnd_opclh),       // オペランドのデータが揃った
                                         // operand data ready
    .RANDOM_FOR_IFRDY (rnd_ifrdy),       // 命令フェッチの要求を受け付けられる
                                         // a fetch request can be accepted
    .RANDOM_FOR_IFCLH (rnd_ifclh),       // フェッチした命令が揃った
                                         // fetched instructions ready
    .PC               (pc)
  );

  always #5 clk = ~clk;                  // 周期 10 のクロック
                                         // clock with period 10

  initial begin
    // --- plusargs を読む ---
    // --- read the plusargs ---
    if (!$value$plusargs("HEX=%s", hexfile)) begin
      $display("usage: vvp sim +HEX=mem.hex +PC=300 +CYCLES=250 [+RANDOM] [+SEED=n]");
      $finish;
    end
    if (!$value$plusargs("PC=%h", reset_pc))   reset_pc = 32'h300;
    if (!$value$plusargs("CYCLES=%d", maxcyc)) maxcyc   = 250;
    if (!$value$plusargs("SEED=%d", seed))     seed     = 1;
    use_random = $test$plusargs("RANDOM");
    trace      = $test$plusargs("TRACE");
    ctrace     = $test$plusargs("CTRACE");

    // メモリイメージを stm_memory の配列に直接読み込む
    // load the memory image directly into the array of stm_memory
    $readmemh(hexfile, u_sys.u_mem.mem);

    // 立ち上がり 2 回の間リセットし, 立ち下がりで解除する
    // hold reset for 2 rising edges and release it on a falling edge
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 1'b0;

    for (cycles = 1; cycles <= maxcyc; cycles = cycles + 1) begin
      // 立ち下がりで乱数入力を更新 (C 版は 1 サイクルごとに random())
      // update the random inputs on the falling edge (the C version calls random() once per cycle)
      // 【解説】この実験版ではオペランド側だけを 3/4 の確率でミスにし, 命令フェッチは
      //         いつもヒットにする (tb/tb_stm.v は 3 本とも 1/2)。
      // [Note] This experimental version makes only the operand side miss with probability 3/4 and
      //        lets instruction fetch always hit (tb/tb_stm.v uses 1/2 for all three).
      if (use_random) begin
        rnd_opclh = (($random(seed) & 15) >= 12);
        rnd_ifrdy = 1;
        rnd_ifclh = 1;
      end
      #1;
      // 【解説】PC は「完了した命令の次の番地」(080_w_act.vh)。その番地の命令が
      //         診断命令 (上位 4bit = 0xD) なら, テストプログラムの終わりに着いた。
      // [Note] PC is "the address after the completed instructions" (080_w_act.vh). If the instruction at that
      //        address is a diagnostic instruction (top 4 bits = 0xD), the test program has reached its end.
      insn = u_sys.u_mem.mem[pc[11:2]];
      if (trace)
        $display("%4d PC=%h D_FWD=%b A_FWD=%b B_FWD=%b E_FWD=%b W_COMPLETE=%b I0=%h I1=%h",
                 cycles, pc, u_sys.u_cntl.D_FWD, u_sys.u_cntl.A_FWD,
                 u_sys.u_cntl.B_FWD, u_sys.u_cntl.E_FWD,
                 u_sys.u_cntl.W_COMPLETE, u_sys.u_cntl.I0, u_sys.u_cntl.I1);
      if (ctrace)   // C 版 siml.res と同じ並び (比較用 form.dat: tools/form_cmp.dat)
                    // same order as siml.res of the C version (form.dat for comparison: tools/form_cmp.dat)
        $display("%h%h%h%h%h%h%h%h%h%h%h%h%h%h%h",
                 pc, u_sys.u_cntl.D_FWD, u_sys.u_cntl.A_FWD, u_sys.u_cntl.B_FWD,
                 u_sys.u_cntl.E_FWD, u_sys.u_cntl.W_COMPLETE,
                 u_sys.u_cntl.I0, u_sys.u_cntl.I1, u_sys.u_cntl.IB_AD,
                 u_sys.u_cntl.LBS_AD, u_sys.u_cntl.W_WDT1, u_sys.u_cntl.W_WDT2,
                 u_sys.u_cntl.PSW_CC, u_sys.u_cntl.NIP_A, u_sys.u_cntl.NIP_B);
      // 終了判定: SUCCESS (0x3F0) なら OK, DEAD (0x3D0) なら NG, それ以外は STOP
      // stop check: OK at SUCCESS (0x3F0), DEAD at 0x3D0, otherwise STOP
      if (insn[31:28] == 4'hD) begin
        if (pc == 32'h3f0)
          $display("RESULT: stop at PC=%h after %0d cycles -> OK", pc, cycles);
        else if (pc == 32'h3d0)
          $display("RESULT: stop at PC=%h after %0d cycles -> DEAD", pc, cycles);
        else
          $display("RESULT: stop at PC=%h after %0d cycles -> STOP", pc, cycles);
        $finish;
      end
      @(negedge clk);
    end
    $display("RESULT: timeout PC=%h after %0d cycles -> TIMEOUT", pc, maxcyc);
    $finish;
  end
endmodule
