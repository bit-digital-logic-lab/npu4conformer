`timescale 1ns/1ps
// Ready-mask banked scanner regression.
// Reference model uses the done_mask snapshot taken at scan_start and selects
// the lowest-index node whose pending bit is set, all dependencies are done,
// and whose engine class is free.
module tb_ready_scan;
 localparam N=128;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,scan_start=0,scan_ack=0;
 reg [N-1:0] pending=0;
 reg [N*128-1:0] dep_flat=0;
 reg [N*3-1:0] type_flat=0;
 reg [127:0] done_mask=0;
 reg [3:0] engine_free=4'hf;
 wire cand_valid,scan_done,scan_busy;
 wire [6:0] cand_id,cand_id_dbg;
 wire [2:0] cand_type;wire [1:0] cand_bank;
 wire [31:0] scan_cycles;
 reg [127:0] done_snap;
 reg [127:0] dep_arr[0:N-1];
 reg [2:0] type_arr[0:N-1];
 integer errors=0,cycles=0;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s at trial %0d",what,cycles);$fflush();end end endtask
 ready_scan_banked_v1 dut(.clk(clk),.rst_n(rst_n),.scan_start(scan_start),.scan_ack(scan_ack),
  .pending(pending),.dep_mask_flat(dep_flat),.node_type_flat(type_flat),.done_mask(done_mask),
  .engine_free(engine_free),.cand_valid(cand_valid),.scan_done(scan_done),.cand_id(cand_id),
  .cand_type(cand_type),.cand_bank(cand_bank),.scan_cycles(scan_cycles),.scan_busy(scan_busy));
 integer i,j,t;
 reg ref_valid;integer ref_id;
 reg [2:0] ref_type;
 task compute_ref;begin
  ref_valid=0;ref_id=-1;ref_type=0;
  for(j=0;j<N;j=j+1)begin
   if(!ref_valid&&pending[j]&&((dep_arr[j]&~done_snap)==0))begin
    if((type_arr[j]==3'd1&&engine_free[1])||(type_arr[j]==3'd2&&engine_free[2])||
       (type_arr[j]==3'd3&&engine_free[3])||(type_arr[j]==3'd4&&engine_free[0]))begin
     ref_valid=1;ref_id=j;ref_type=type_arr[j];
    end
   end
  end
 end endtask
 task build_flat;begin
  for(j=0;j<N;j=j+1)begin dep_flat[j*128+:128]=dep_arr[j];type_flat[j*3+:3]=type_arr[j];end
 end endtask
 task do_scan;begin
  @(negedge clk);scan_start=1;done_snap=done_mask;
  @(posedge clk);@(negedge clk);scan_start=0;
  cycles=0;
  while(!cand_valid&&!scan_done&&cycles<20)begin @(posedge clk);cycles=cycles+1;end
  compute_ref;
  if(cycles>=20)begin
   $display("DBG timeout state=%0d busy=%0d cand=%0d done=%0d picked=%0d refv=%0d refid=%0d pend_snap=%h done_snap=%h ef=%h",
     dut.state,scan_busy,cand_valid,scan_done,dut.picked,ref_valid,ref_id,dut.pend_snap,done_snap,engine_free);
   $display("DBG cand_i=%0d,%0d,%0d,%0d pick=%0d cid=%0d ctype=%0d cv=%0d,%0d,%0d,%0d pendbit=%0d",
     dut.cand_i[0],dut.cand_i[1],dut.cand_i[2],dut.cand_i[3],dut.pick_bank,dut.cand_id,dut.cand_type,
     dut.cand_v[0],dut.cand_v[1],dut.cand_v[2],dut.cand_v[3],pending[dut.cand_id]);$fflush();
  end
  if((ref_valid!==cand_valid)||(ref_valid&&(cand_id!==ref_id[6:0])))begin
   $display("MISMATCH t=%0d refv=%0d refid=%0d candv=%0d cid=%0d cyc=%0d state=%0d busy=%0d pend_snap=%h done_snap=%h ef=%h",
     t,ref_valid,ref_id,cand_valid,cand_id,cycles,dut.state,scan_busy,dut.pend_snap,done_snap,engine_free);
   $display("  dep[cid]=%h flat[cid]=%h dep[ref]=%h dutdone=%h pending=%h",dep_arr[cand_id],dep_flat[cand_id*128+:128],(ref_id>=0?dep_arr[ref_id]:0),dut.done_snap,pending);$fflush();
  end
  if(ref_valid)begin
   chk("candidate present",cand_valid);
   if(cand_valid)begin
    chk("candidate id",cand_id==ref_id[6:0]);
    chk("candidate type",cand_type==ref_type);
    chk("candidate dep satisfied",(dep_arr[cand_id]&~done_snap)==0);
    chk("candidate engine free",(cand_type==1&&engine_free[1])||(cand_type==2&&engine_free[2])||
       (cand_type==3&&engine_free[3])||(cand_type==4&&engine_free[0]));
   end
  end else begin
   chk("no candidate",!cand_valid);
   chk("scan_done pulse",scan_done);
  end
  chk("scan latency",cycles<=7);
  @(negedge clk);scan_ack=1;@(posedge clk);@(negedge clk);scan_ack=0;
  repeat(2)@(posedge clk);
 end endtask
 integer seed=32'h1234567;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  // deterministic: all pending, all deps zero, all engines free -> node 0
  for(i=0;i<N;i=i+1)begin pending[i]=1;dep_arr[i]=0;type_arr[i]=2'd1;end
  done_mask=0;engine_free=4'hf;build_flat;do_scan;
  $display("SCAN_ALL_READY id=%0d type=%0d cycles=%0d",cand_id,cand_type,cycles);
  chk("all-ready lowest",cand_id==0);

  // only node 127 ready
  pending=0;pending[127]=1;for(i=0;i<N;i=i+1)dep_arr[i]=0;build_flat;do_scan;
  $display("SCAN_NODE127 id=%0d cycles=%0d",cand_id,cycles);
  chk("node127 selected",cand_id==127);

  // engine class filter: all pending type 2, only LAY engine free -> no candidate
  for(i=0;i<N;i=i+1)begin pending[i]=1;dep_arr[i]=0;type_arr[i]=2'd2;end
  engine_free=4'b1000;build_flat;do_scan;
  chk("engine filtered no candidate",!cand_valid);

  // dependency chain: node 127 depends on 126, done 126 -> node 127
  pending=0;pending[126]=0;pending[127]=1;dep_arr[127]=0;dep_arr[127][126]=1;
  done_mask=0;done_mask[126]=1;engine_free=4'hf;build_flat;do_scan;
  chk("dep chain",cand_id==127);

  // same chain without done -> no candidate
  pending=0;pending[127]=1;done_mask=0;build_flat;do_scan;
  chk("unmet dep rejected",!cand_valid);

  // randomized: lower-index-only dep masks, changing done/pending during scan.
  for(t=0;t<400;t=t+1)begin
   for(i=0;i<N;i=i+1)begin
    pending[i]=(($random(seed)&1)!=0);
    dep_arr[i]=0;
    for(j=0;j<i;j=j+1)if(($random(seed)&31)==0)dep_arr[i][j]=1'b1;
    type_arr[i]=(($random(seed)&3)+1);
   end
   done_mask=0;
   for(i=0;i<N;i=i+1)if(($random(seed)&1)!=0)done_mask[i]=1'b1;
   engine_free=$random(seed);
   build_flat;
   // change done mask during scan (after snapshot); reference uses old snapshot
   fork
    begin do_scan; end
    begin @(posedge clk);@(posedge clk);done_mask=done_mask|($random(seed));end
   join
   // reset pending for next trial (do_scan does not consume it in the model)
  end
  $display("READY_SCAN_TEST_END errors=%0d",errors);$fflush();
  if(errors==0)$display("READY_SCAN_PASS");else $display("READY_SCAN_FAIL");
  $finish;
 end
 initial begin repeat(200000)@(posedge clk);$display("READY_SCAN_TIMEOUT");$finish;end
endmodule
