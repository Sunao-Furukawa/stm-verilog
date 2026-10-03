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
// =====================================================================
module tb_stm;
  reg         clk = 1'b0;
  reg         rst = 1'b1;
  reg  [31:0] reset_pc;
  reg         rnd_opclh = 1'b1, rnd_ifrdy = 1'b1, rnd_ifclh = 1'b1;
  wire [31:0] pc;

  reg  [1023:0] hexfile;
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
