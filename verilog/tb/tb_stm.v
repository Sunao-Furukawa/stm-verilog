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
module tb_stm;
  reg         clk = 1'b0;
  reg         rst = 1'b1;
  reg  [31:0] reset_pc;
  reg         rnd_opclh = 1'b1, rnd_ifrdy = 1'b1, rnd_ifclh = 1'b1;
  wire [31:0] pc;

  reg  [8*1024-1:0] hexfile;     // +HEX= のファイル名 (最大 1024 文字)
  integer       cycles, maxcyc, seed;
  reg           use_random, trace, ctrace;
  reg  [31:0]   insn;

  stm_sys u_sys (
    .clk              (clk),
    .rst              (rst),
    .RESET_PC         (reset_pc),
    .RANDOM_FOR_OPCLH (rnd_opclh),
    .RANDOM_FOR_IFRDY (rnd_ifrdy),
    .RANDOM_FOR_IFCLH (rnd_ifclh),
    .PC               (pc)
  );

  always #5 clk = ~clk;

  // コンソール: F000_0008 へのストアで 1 文字表示
  always @(posedge clk)
    if (!rst && u_sys.u_mem.we && u_sys.u_mem.opad == 32'hf000_0008)
      $write("%c", u_sys.u_mem.stdt[7:0]);

  initial begin
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

    $readmemh(hexfile, u_sys.u_mem.mem);

    repeat (2) @(posedge clk);
    @(negedge clk) rst = 1'b0;

    for (cycles = 1; cycles <= maxcyc; cycles = cycles + 1) begin
      // 立ち下がりで乱数入力を更新 (C 版は 1 サイクルごとに random())
      if (use_random) begin
        rnd_opclh = (($random(seed) & 15) >= 8);
        rnd_ifrdy = (($random(seed) & 15) >= 8);
        rnd_ifclh = (($random(seed) & 15) >= 8);
      end
      #1;
      // 【解説】PC は「完了した命令の次の番地」(080_w_act.vh)。その番地の命令が
      //         診断命令 (上位 4bit = 0xD) なら、テストプログラムの終わりに着いた。
      // [Note] PC is "the address after the completed instructions" (080_w_act.vh). If the instruction at that
      //        address is a diagnostic instruction (top 4 bits = 0xD), the test program has reached its end.
      insn = u_sys.u_mem.mem[pc[11:2]];
      if (trace)
        $display("%4d PC=%h D_FWD=%b A_FWD=%b B_FWD=%b E_FWD=%b W_COMPLETE=%b I0=%h I1=%h",
                 cycles, pc, u_sys.u_cntl.D_FWD, u_sys.u_cntl.A_FWD,
                 u_sys.u_cntl.B_FWD, u_sys.u_cntl.E_FWD,
                 u_sys.u_cntl.W_COMPLETE, u_sys.u_cntl.I0, u_sys.u_cntl.I1);
      if (ctrace)   // C 版 siml.res と同じ並び (比較用 form.dat: tools/form_cmp.dat)
        $display("%h%h%h%h%h%h%h%h%h%h%h%h%h%h%h",
                 pc, u_sys.u_cntl.D_FWD, u_sys.u_cntl.A_FWD, u_sys.u_cntl.B_FWD,
                 u_sys.u_cntl.E_FWD, u_sys.u_cntl.W_COMPLETE,
                 u_sys.u_cntl.I0, u_sys.u_cntl.I1, u_sys.u_cntl.IB_AD,
                 u_sys.u_cntl.LBS_AD, u_sys.u_cntl.W_WDT1, u_sys.u_cntl.W_WDT2,
                 u_sys.u_cntl.PSW_CC, u_sys.u_cntl.NIP_A, u_sys.u_cntl.NIP_B);
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
