/// High Level Packet Size
`define HDATA_SIZE 127
/// Low Level Packet Size
`define LDATA_SIZE 63
/// Interface Data Size
`define INTF_DATA_SIZE 3
/// No. Of Loops for High Level Packet in one TOP SEQ
`define NO_OF_LOOPS 5
/// Lower Frame Size
`define LFRAME_SIZE ((`LDATA_SIZE+1)/(`INTF_DATA_SIZE + 1))
/// No. of time TOP Sequence is started
`define SEQ_START 5
