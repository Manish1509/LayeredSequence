/// Manish Singhal
/// Layering Agent ////

//////////////////////////////////////////
/// Upper Layer Item Declaration//////////
//////////////////////////////////////////
class high_level_item extends uvm_sequence_item;
  `uvm_object_utils(high_level_item)
  
  rand logic [`HDATA_SIZE:0] hi_data;
  rand int delay;
  
  constraint c_delay { delay > 0; delay < 20; }
  
  function new (string name = "");
    super.new(name);
  endfunction: new
  
endclass: high_level_item




///////////////////////////////////////
/// Layering Sequencer Declaration/////
///////////////////////////////////////
typedef uvm_sequencer #(high_level_item) layering_sequencer;


//////////////////////////////////////////////////////
/// Top Level Sequence (Which we want to re-use) /////
//////////////////////////////////////////////////////
class top_seq extends uvm_sequence #(high_level_item);
  `uvm_object_utils(top_seq)
  
  high_level_item h_item;
  
  function new (string name = "top_seq");
    super.new(name);
  endfunction: new
  
  task body;
    for (int j=0; j<`NO_OF_LOOPS; j++) begin
    h_item = high_level_item::type_id::create("h_item");
//    for(int i=0; i<8; i++) begin
    start_item(h_item);
    if(!h_item.randomize())
      `uvm_error("high_level_item", "randomization failed")
      $display("high level data is = %h", h_item.hi_data);
    finish_item(h_item);
//    end
    end
  endtask: body
  
endclass: top_seq
    
 ////////////////////////////////////////////
/// Translator Sequence Declaration ////////
////////////////////////////////////////////
class translator_seq extends uvm_sequence #(adpcm_seq_item);
  `uvm_object_utils(translator_seq)
  
  function new (string name= "");
    super.new(name);
  endfunction: new
  
  uvm_sequencer #(high_level_item) up_sequencer;
  
  task body;
    
    adpcm_seq_item l_item;
    high_level_item h_item;
    
    forever begin
      up_sequencer.get_next_item(h_item);
      l_item = adpcm_seq_item::type_id::create("l_item");

      
      start_item(l_item);
      l_item.data = h_item.hi_data[`HDATA_SIZE:(`LDATA_SIZE + 1)];
      l_item.delay = h_item.delay;
      finish_item(l_item);
      
      l_item = adpcm_seq_item::type_id::create("l_item");
      
      start_item(l_item);
      h_item.hi_data = h_item.hi_data << (`LDATA_SIZE + 1);
      l_item.data = h_item.hi_data[`HDATA_SIZE:(`LDATA_SIZE + 1)];
      l_item.delay = h_item.delay;
//      l_item.data = h_item.hi_data[3:0];
      finish_item(l_item);
            
      up_sequencer.item_done();
    end
    
  endtask: body
  
endclass: translator_seq


////////////////////////////////////////
///// Layering Monitor ///////////////
///////////////////////////////////////

//`uvm_analysis_imp_decl(_in)
//`uvm_analysis_imp_decl(_out)

class layering_monitor extends uvm_monitor #(adpcm_seq_item);
  `uvm_component_utils(layering_monitor)
  
  int rot = 0; // Integer to control incoming frames from lower monitor.
  int newd = 0;
  
  /// Analysis export declaration
  uvm_analysis_imp #(adpcm_seq_item, layering_monitor) xport;
  
  /// Analysis port to send the data from layering monitor -> scoreboard
  uvm_analysis_port #(adpcm_seq_item) ap_lmon;
  
  
  high_level_item highitem_in, highitem_out;
  adpcm_seq_item lowitem_in, lowitem_out; 
      
  function new (string name, uvm_component parent);
    super.new(name, parent);
    xport = new("xport", this);
    ap_lmon = new("ap_lmon", this);
  endfunction: new
  
  
  
  task main_phase (uvm_phase phase);
    
    highitem_in = high_level_item::type_id::create("highitem_in", this);
    
 //   forever
 //     begin
 //       if(rot == 1) begin
 //         highitem_in = high_level_item::type_id::create("highitem_in", this);
 //        end
 //     end

  endtask
      
  
  function void write(adpcm_seq_item seqitem);
    
    lowitem_in = adpcm_seq_item::type_id::create("lowitem_in", this);
    
    if (newd == 1) begin
    highitem_in = high_level_item::type_id::create("highitem_in", this);
    newd = 0;
    end
    
//    if (rot == 1)
//      highitem_in = high_level_item::type_id::create("highitem_in", this);
    
    lowitem_in = seqitem;
    
    /// Calling write() function call to send data to scoreboard
    ap_lmon.write(seqitem);
    
    `uvm_info("LAYERING MONITOR", $sformatf("Received Data from Lower Monitor = %h", lowitem_in.data), UVM_MEDIUM);
    
    if (rot == 0) begin
      highitem_in.hi_data[`LDATA_SIZE:0] = lowitem_in.data;
      rot++;
      `uvm_info("LAYERING MONITOR", $sformatf("Received High Level Frame (1) = %h", highitem_in.hi_data), UVM_HIGH);
    end
    else if (rot == 1) begin
      highitem_in.hi_data[`HDATA_SIZE:(`LDATA_SIZE + 1)] = lowitem_in.data;
      rot = 0;
      newd++;
      `uvm_info("LAYERING MONITOR", $sformatf("Received High Level Frame (2) = %h", highitem_in.hi_data), UVM_HIGH);
    end
   
    
  endfunction: write
    

endclass: layering_monitor




///////////////////////////////////////
/// Layering Agent Declaration ////////
///////////////////////////////////////
class layering_agent extends uvm_agent #(adpcm_seq_item);
  `uvm_component_utils(layering_agent)
  
  /// Handle for ADPCM Agent
  my_agent m_agnt;
  
  /// Layering Sequencer
  layering_sequencer l_sqr;
  
  /// Layering Monitor
  layering_monitor l_mon;
  
  /// Analysis export to connect the Layering monitor's analysis export
  uvm_analysis_imp #(adpcm_seq_item, layering_agent) l_xport;
  
  /// Analysis port to connect the Layering monitor's port 
  uvm_analysis_port #(adpcm_seq_item, layering_agent) ap_l_agnt;
  
  /// Translator Sequence
  translator_seq trans_seq;
  
  function new (string name, uvm_component parent);
    super.new(name, parent);
    l_xport = new("l_xport", this);
    ap_l_agnt = new("ap_l_agnt", this);
  endfunction: new
  
   
  function void build_phase (uvm_phase phase);
    l_sqr = layering_sequencer::type_id::create("l_sqr", this);
    l_mon = layering_monitor::type_id::create("l_mon", this);
  endfunction: build_phase
  
  function void connect_phase (uvm_phase phase);
//    l_mon.xport.connect(l_xport);
    /// Connecting the Layering agent's analysis ports and Layering monitor's analysis port
    //    ap_l_agnt.connect(l_mon.ap_lmon); /// Its wrong, connected in opposite way.
    l_mon.ap_lmon.connect(ap_l_agnt);
  endfunction: connect_phase
  
    task main_phase (uvm_phase phase);
    trans_seq = translator_seq::type_id::create("trans_seq");
      
//      m_agnt.m_sqr.ADPCM.cb.trans <= 1;
    
    /// Connecting the translator sequence up_sequncer to respective sequencer
    trans_seq.up_sequencer = l_sqr;
    
    /// Start the translator sequence
    fork
//      @(m_agnt.m_sqr.ADPCM.cb.trans == 1) begin
      trans_seq.start(m_agnt.m_sqr);
        `uvm_info("TSEQ", "TRANSLATOR SEQUENCE EXECUTED...", UVM_MEDIUM);
//      end
    join_none
    
  endtask: main_phase
  /// Very Important Code to Connect Layering agent export to Layering monitor export.
  function void write(adpcm_seq_item t);
    l_mon.write( t );
  endfunction: write
    
  
  
endclass: layering_agent
