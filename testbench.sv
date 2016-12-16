package adpcm_pkg;

import uvm_pkg::*;
`include "uvm_macros.svh"
//`include "layering_agent.sv"

// Sequence item contains the data and a delay before
// sending the data frame

//
class adpcm_seq_item extends uvm_sequence_item;

rand logic[`LDATA_SIZE:0] data;
//  logic [`INTF_DATA_SIZE:0] data_q [$];
rand int delay;

constraint c_delay { delay > 0; delay <= 20; }
  
`uvm_object_utils(adpcm_seq_item)

function new(string name = "adpcm_seq_item");
  super.new(name);
endfunction

function void do_copy(uvm_object rhs);
  adpcm_seq_item rhs_;

  if(!$cast(rhs_, rhs)) begin
    uvm_report_error("do_copy", "cast failed, check types");
  end
  data = rhs_.data;
  delay = rhs_.delay;
endfunction: do_copy

function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  adpcm_seq_item rhs_;

  do_compare = $cast(rhs_, rhs) &&
               super.do_compare(rhs, comparer) &&
               data == rhs_.data &&
               delay == rhs_.delay;
endfunction: do_compare

function string convert2string();
  return $sformatf(" data:\t%0h\n delay:\t%0d", data, delay);
endfunction: convert2string

function void do_print(uvm_printer printer);

  if(printer.knobs.sprint == 0) begin
    $display(convert2string());
  end
  else begin
    printer.m_string = convert2string();
  end

endfunction: do_print

function void do_record(uvm_recorder recorder);
  super.do_record(recorder);

  `uvm_record_field("data", data);
  `uvm_record_field("delay", delay);

endfunction: do_record

endclass: adpcm_seq_item

// Unidirectional driver uses the get_next_item(), item_done() approach
//
class adpcm_driver extends uvm_driver #(adpcm_seq_item);

`uvm_component_utils(adpcm_driver)

adpcm_seq_item txn;
int i = 0;

virtual adpcm_if.mon_mp ADPCM;
  
/// Declaration of an Analysis port going to -> Scoreboard  
  uvm_analysis_port #(adpcm_seq_item) ap_drv;

function new(string name = "adpcm_driver", uvm_component parent = null);
  super.new(name, parent);
  ap_drv = new("ap_drv", this);
endfunction
  
  task reset_phase (uvm_phase phase);
  
  // Default conditions:
  ADPCM.cb.frame <= 0;
  ADPCM.cb.data <= 0;
  ADPCM.cb.trans <= 1;
    
  endtask: reset_phase
  
  
task main_phase(uvm_phase phase);
  int top_idx = 0;
  int loops = 1;


  fork
  forever
    begin
      txn = adpcm_seq_item::type_id::create("txn", this);
      seq_item_port.get_next_item(txn); // Gets the sequence_item from the sequence
      $display("Data received = %h", txn.data);

      /// Sending the transaction i.e. req to the Scoreboard
      ap_drv.write(txn);
      
      repeat(txn.delay) begin // Delay between packets
        @(ADPCM.cb);

      end

      repeat((`LDATA_SIZE + 1)/4) begin
        @(ADPCM.cb);
        ADPCM.cb.frame <= 1; // Start of frame
        ADPCM.cb.trans <= 1; // Start of Data Transmission
        ADPCM.cb.data <= txn.data[`INTF_DATA_SIZE:0];
        txn.data = txn.data >> (`INTF_DATA_SIZE + 1);
      end

        @(ADPCM.cb);      
        ADPCM.cb.frame <= 0; // End of frame
        ADPCM.cb.data <= 4'bz;  

      if (loops >= 2*`NO_OF_LOOPS) begin
        ADPCM.cb.trans <= 0;
        loops = 0;
      end
          else
          ADPCM.cb.trans <= 1;  

      seq_item_port.item_done(); // Indicates that the sequence_item has been consumed
      loops++;
//      $display("Loops = %d", loops);
    end
/*  forever begin
    @(ADPCM.cb);
    if (ADPCM.cb.frame === 1'b1) begin
      ADPCM.cb.trans <= 1;
//      $display($time);
    end
  end */
  join  
  
  
endtask: main_phase
  
/* virtual function void phase_ready_to_end (uvm_phase phase);
  `uvm_info("PMH", "Above statement", UVM_MEDIUM);
  ADPCM.cb.trans <= 0; // End of Data Transmission
  `uvm_info("PMH", "Below statement", UVM_MEDIUM);
endfunction */
/*  
task shutdown_phase(uvm_phase phase);
//  forever begin
  super.shutdown_phase(phase);
  phase.raise_objection(this);
    `uvm_info("PMH", "Above statement", UVM_MEDIUM);
 
  @(ADPCM.cb);
    ADPCM.cb.trans <= 0; // End of Data Transmission   

    `uvm_info("PMH", "Below statement", UVM_MEDIUM);
  phase.drop_objection(this);
//  end
  endtask 
*/        
  
endclass: adpcm_driver


//// ADPCM Monitor
class adpcm_monitor extends uvm_monitor #(adpcm_seq_item);
  `uvm_component_utils(adpcm_monitor)
  
  /// Queue to hold incoming data
  logic [`INTF_DATA_SIZE:0] data_q [$];
  int N = 0;
  int M = 0;
  int Y = 1;
  logic ProcessDone = 0;
  
  virtual adpcm_if.mon_mp ADPCM;
  
  adpcm_seq_item litem;
  
  /// Analysis Port Declartion 
  uvm_analysis_port #(adpcm_seq_item) apl;
  

  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction: new
  
  function void build_phase (uvm_phase phase);
    apl = new("apl", this);
  endfunction: build_phase
  
  task main_phase (uvm_phase phase);
    litem = adpcm_seq_item::type_id::create("litem", this);

        
    forever
       begin
           
         fork begin

           @(ADPCM.cb);
         // for(int m = 0; m<((`LDATA_SIZE + 1)/4); m++) begin
           if ((ADPCM.cb.frame == 1) && (ADPCM.cb.trans == 0)) begin 
             data_q.push_back(ADPCM.cb.data);
//             $display("Data in Monitor Queue = %p", data_q);
             litem.data = litem.data >> (`INTF_DATA_SIZE + 1);
             litem.data[(`LDATA_SIZE):(`LDATA_SIZE - `INTF_DATA_SIZE)] = data_q.pop_front();
             `uvm_info("L_MON", $sformatf("Data Received in Monitor = %h", litem.data), UVM_HIGH);
            M++;
             `uvm_info("L_MON", $sformatf("Value of M* = %0d", M), UVM_HIGH);
             end
               
      
           for (Y = 1; Y < ((2*`NO_OF_LOOPS*`SEQ_START) + 1); Y++) begin
             //$display("Y = %0d", Y); // Purpose of Y is to change the multiple & match value for LFRAME_SIZE.  
             if ((ADPCM.cb.frame == 1) && (ADPCM.cb.trans == 0)) begin       	          
               if (M == (Y*(`LFRAME_SIZE))) begin
//                $display("#########################################");
                 `uvm_info("AGENT MONITOR", $sformatf("        Lower Monitor data is = %h", litem.data), UVM_MEDIUM);
//                $display("#########################################");
                 `uvm_info("L_MON", $sformatf("Value of M = %0d", M), UVM_HIGH);
                /// Calling the Write Function
                apl.write(litem);
              end 
             end
           end  
             
       end
     join         
            
    end
  

 endtask: main_phase
  
  
  task wait_to_be_done();
    @(M == ((2*`NO_OF_LOOPS*(`SEQ_START)*`LFRAME_SIZE)))    
    ProcessDone = 1;
    `uvm_info("MONITOR", "Monitor Processing Done!", UVM_MEDIUM);
  endtask: wait_to_be_done
  
  
  function void phase_ready_to_end (uvm_phase phase);
//    if (phase.is(uvm_main_phase::get)) begin
    if(phase.get_name == "main") begin
      if(!ProcessDone == 1'b1) begin
       phase.raise_objection(this);
       fork begin
        `uvm_info("MONITOR", "Monitor is in progress..", UVM_MEDIUM);
         wait_to_be_done();
         phase.drop_objection(this);
       end
       join_none 
     end
    end
  endfunction  
  

    
    
  
endclass: adpcm_monitor

//////////////////////////////////////////////////
/////////////////////////////////////////////////

class adpcm_sequencer extends uvm_sequencer #(adpcm_seq_item);

`uvm_component_utils(adpcm_sequencer)

  
  virtual adpcm_if.mon_mp ADPCM;
  
  
  function new(string name = "adpcm_sequencer", uvm_component parent = null);
   super.new(name, parent);
  endfunction

endclass: adpcm_sequencer

// Sequence part of the use model
//
// The sequence randomizes 10 ADPCM data packets and sends
// them
//
class adpcm_tx_seq extends uvm_sequence #(adpcm_seq_item);

`uvm_object_utils(adpcm_tx_seq)

// ADPCM sequence_item
adpcm_seq_item req;

// Controls the number of request sequence items sent
rand int no_reqs = 10;

function new(string name = "adpcm_tx_seq");
  super.new(name);
  // do_not_randomize = 1'b1; // Required for ModelSim
endfunction

task body;
  req = adpcm_seq_item::type_id::create("req");

  for(int i = 0; i < no_reqs; i++) begin
    start_item(req);
    // req.randomize();
    // For ModelSim, use $urandom to achieve randomization for your request
    req.delay = $urandom_range(1, 20);
    req.data = $urandom();
    finish_item(req);
    `uvm_info("ADPCM_TX_SEQ_BODY", $sformatf("Transmitted frame %0d", i), UVM_LOW)
  end
endtask: body

endclass: adpcm_tx_seq

class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)
  
adpcm_driver m_driver;
adpcm_sequencer m_sqr;
adpcm_monitor m_mon;  
  
  /// Analysis Port for data flowing towards Layering Agent
  uvm_analysis_port #(adpcm_seq_item) ap;
  /// Analysis Port for data flowing towards Scoreboard
  uvm_analysis_port #(adpcm_seq_item) ap_my_agnt;

  function new(string name = "my_agent", uvm_component parent = null);
  super.new(name, parent);
endfunction

function void build_phase(uvm_phase phase);
  m_driver = adpcm_driver::type_id::create("m_driver", this);
  m_sqr = adpcm_sequencer::type_id::create("m_sqr", this);
  m_mon = adpcm_monitor::type_id::create("m_mon", this);
  ap = new("ap", this);
  ap_my_agnt = new("ap_my_agnt", this);
endfunction: build_phase

function void connect_phase(uvm_phase phase);
  m_driver.seq_item_port.connect(m_sqr.seq_item_export);
  
  /// Driver Connection to the Virtual Interface
  if (!uvm_config_db #(virtual adpcm_if.mon_mp)::get(this, "",
    "ADPCM_vif", m_driver.ADPCM)) begin
    `uvm_error("Connect", "ADPCM_vif not found")
  end
  
  /// Monitor Connection to the Virtual Interface
  if (!uvm_config_db #(virtual adpcm_if.mon_mp)::get(this, "", "ADPCM_vif", m_mon.ADPCM)) begin
    `uvm_error("Connect", "ADPCM_vif not found")
  end
  
    /// Sequencer Connection to the Virtual Interface
  if (!uvm_config_db #(virtual adpcm_if.mon_mp)::get(this, "", "ADPCM_vif", m_sqr.ADPCM)) begin
    `uvm_error("Connect", "ADPCM_vif not found")
  end
  
  /// Analysis Ports Connection between Agent(ap) and its Monitor(apl)
  m_mon.apl.connect(ap);
  
  /// Analysis Ports Connection between Agent(ap_my_agnt) and its Driver(ap_drv)
  m_driver.ap_drv.connect(ap_my_agnt);
  
endfunction: connect_phase
  
endclass: my_agent  

`include "layering_agent.sv"

////////////////////////////////
//// UVM Scoreboard ////////////
////////////////////////////////
`uvm_analysis_imp_decl(_drv)
`uvm_analysis_imp_decl(_mon)
class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)
  
  int pass_cnt = 0;
  int fail_cnt = 0;
  int check_done = 0;

    adpcm_seq_item drv_q [$];
    adpcm_seq_item mon_q [$];
  
  uvm_analysis_imp_drv #(adpcm_seq_item, my_scoreboard) scb_drv;
  uvm_analysis_imp_mon #(adpcm_seq_item, my_scoreboard) scb_mon;
  
  function new (string name, uvm_component parent);
    super.new(name, parent);
    scb_drv = new("scb_drv", this);
    scb_mon = new("scb_mon", this);
  endfunction: new
  
  function void write_drv(adpcm_seq_item seq1);
    
    adpcm_seq_item drv_item;
    drv_item = adpcm_seq_item::type_id::create("drv_item", this);
    
    drv_item.do_copy(seq1);

    drv_q.push_back(drv_item);
    $display("Size of the Driver Queue is = %0d", drv_q.size());
    `ifdef QDATA
    $write("Driver Queue contains Transactions with Data = ");
    foreach (drv_q[i]) begin
      $write("%h ", drv_q[i].data);
    end
    $write("\n");
    `endif
  endfunction: write_drv
  
  function void write_mon(adpcm_seq_item seq2);
    
    adpcm_seq_item mon_item;
    mon_item = adpcm_seq_item::type_id::create("mon_item", this);
    
    mon_item.do_copy(seq2);
    
    mon_q.push_back(mon_item);
    $display("Size of the Monitor Queue is = %0d", mon_q.size());
    `ifdef QDATA
    $write("Monitor Queue contains Transactions with Data = ");
    //    $display("%p", mon_q); /// To print the queue as a whole.
    foreach (mon_q[i]) begin
      $write("%h ", mon_q[i].data);
    end
    $write("\n");
    `endif
  endfunction: write_mon
  
  task shutdown_phase (uvm_phase phase);
    check_status();
    check_done = 1;
  endtask: shutdown_phase
  
  function void check_status();
    $display("Input Queue size = %0d", drv_q.size());
    $display("Output Queue size = %0d", mon_q.size());
    
    for (int i = 0; i < 2*`NO_OF_LOOPS*`SEQ_START; i++) begin
      if (drv_q[i].data == mon_q[i].data) begin
        $display("Data Matched, drv_q[%0d] = %h and mon_q[%0d] = %h", i, drv_q[i].data, i, mon_q[i].data);
        pass_cnt++;
      end
        else begin
          `uvm_error("scb", $sformatf("Data Mis-Matched, drv_q[%0d] = %h and mon_q[%0d] = %h", i, drv_q[i].data, i, mon_q[i].data));
          fail_cnt++;
        end
    end
    
    drv_q.delete();
    mon_q.delete();
    
    if (fail_cnt == 0) begin
    $display ("#############################################");
    $display ("############### TEST PASSED #################");
    $display ("#############################################");
    end
    else
    $display ("############### TEST FAILED #################");
    
  endfunction: check_status
  
/*  function void phase_ready_to_end (uvm_phase phase);
    if (phase.is(uvm_shutdown_phase::get)) begin
      phase.raise_objection(this);
      fork begin
        `uvm_info("SCOREBOARD", "Status Check is in progress..", UVM_MEDIUM);
        if(check_done == 1) begin
          `uvm_info("SCOREBOARD", "Status Checked Done!", UVM_MEDIUM);
        end
        phase.drop_objection(this);
      end
      join_none
    end
    
  endfunction */
                                 
endclass: my_scoreboard           

////////////////////////////////
///// Environment Class ////////
////////////////////////////////
class my_env extends uvm_env;
  `uvm_component_utils(my_env)
  
  my_agent m_agnt;
  layering_agent l_agnt;
  my_scoreboard my_scb;
  
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction: new
  
  function void build_phase (uvm_phase phase);
    m_agnt = my_agent::type_id::create("m_agnt", this);
    l_agnt = layering_agent::type_id::create("l_agnt", this);
    my_scb = my_scoreboard::type_id::create("my_scb", this);
  endfunction: build_phase
  
  function void connect_phase (uvm_phase phase);
    l_agnt.m_agnt = m_agnt;
    /// my_agent <-> layering_agent
    m_agnt.ap.connect(l_agnt.l_xport);
    /// my_agent <-> scoreboard
    m_agnt.ap_my_agnt.connect(my_scb.scb_drv);
    /// layerng_agent <-> scoreboard
    l_agnt.ap_l_agnt.connect(my_scb.scb_mon);
  endfunction: connect_phase
  
endclass: my_env

// Test instantiates, builds and connects the driver and the sequencer
// then runs the sequence
//
class adpcm_test extends uvm_test;

`uvm_component_utils(adpcm_test)

// adpcm_tx_seq test_seq; // Commented Manish to implement Layered Sequence
top_seq tseq;
my_env env;

function new(string name = "adpcm_test", uvm_component parent = null);
  super.new(name, parent);
endfunction
  
  function void build_phase(uvm_phase phase);
    env = my_env::type_id::create("env", this);
  endfunction: build_phase

task main_phase(uvm_phase phase);
  
/*  
  test_seq = adpcm_tx_seq::type_id::create("test_seq");
  
  phase.raise_objection(this, "starting test_seq");
  test_seq.start(env.m_agnt.m_sequencer);
  phase.drop_objection(this, "finished test_seq");
*/  
  
  /// Top Level Sequence which we want to re-use
  tseq = top_seq::type_id::create("tseq");
  
  phase.raise_objection(this);
  for(int a = 0; a<`SEQ_START; a++) begin 
    @(posedge env.m_agnt.m_sqr.ADPCM.cb.trans) begin
      `uvm_info("TOPSEQ", "TOP SEQ STARTING...", UVM_MEDIUM); 
    tseq.start(env.l_agnt.l_sqr);
      `uvm_info("TOPSEQ", "TOP SEQ FINISHING...", UVM_MEDIUM);
    end
   
//  #3000;
//  #3000; // Put raise and drop objections in scoreboard.
  end
//  tseq.start(env.l_agnt.l_sqr);
//  #3000;
  phase.drop_objection(this);
 
  endtask: main_phase

endclass: adpcm_test

endpackage: adpcm_pkg


module top_tb;

import uvm_pkg::*;
import adpcm_pkg::*;

/// Interface Instantiation
adpcm_if ADPCM();
  
/// DUT Instantiation
dut_adpcm DUT1 (.intf_dut(ADPCM)
                 );

/// Free running clock
initial
  begin
    ADPCM.clk = 0;
    forever begin
      #10 ADPCM.clk = ~ADPCM.clk;
    end
  end

/// UVM start up:
initial
  begin
    uvm_config_db #(virtual adpcm_if.mon_mp)::set(null, "uvm_test_top.*", "ADPCM_vif" , ADPCM);
    run_test("adpcm_test");
  end
  
// Dump waves
  initial 
    begin
      $dumpfile("dump.vcd");
      $dumpvars(0, top_tb);
    end

endmodule: top_tb
