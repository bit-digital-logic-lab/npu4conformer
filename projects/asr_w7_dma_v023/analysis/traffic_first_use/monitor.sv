module ledger_monitor;
 integer fd,c=0;
 initial begin fd=$fopen("signals.csv","w");$fdisplay(fd,"cycle,reqr,reqw,doner,donew,ar,arlen,rv,rr,rl,aw,awlen,wv,wr,ws,b");end
 always @(posedge tb_dma_compare.clk) if(tb_dma_compare.rst_n)begin
 $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",c,
 tb_dma_compare.rd_req_valid&&tb_dma_compare.rd_req_ready,tb_dma_compare.wr_req_valid&&tb_dma_compare.wr_req_ready,
 tb_dma_compare.rd_done,tb_dma_compare.wr_done,tb_dma_compare.ar0_valid&&tb_dma_compare.ar0_ready,tb_dma_compare.ar0_len,
 tb_dma_compare.r0_valid,tb_dma_compare.r0_ready,tb_dma_compare.r0_last,
 tb_dma_compare.aw1_valid&&tb_dma_compare.aw1_ready,tb_dma_compare.aw1_len,
 tb_dma_compare.w1_valid,tb_dma_compare.w1_ready,tb_dma_compare.w1_strb,tb_dma_compare.b1_valid&&tb_dma_compare.b1_ready);
 c=c+1;$fflush(fd);
 end
 endmodule
