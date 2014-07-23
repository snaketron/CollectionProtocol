#ifndef TABLE_H
#define TABLE_H


enum {	
  /**the total number of nodes in the network.*/
  MAX_NODES = 40,
  
  /**the total number of neighbors of a node.*/
  MAX_NEIGHBOR = 8,
  
  /**the size of the array from which the mean rssi is computed.*/  
  MAX_RSSI = 20, 
  
  /**dummy value to point out irregularity or unasigned values.*/
  DUMMY = 255,
};

/**
 * Table used by the LinkComponent to establish the routing tree. 
 * It is an integral part of the PersonlTable.
 **/
typedef struct NeighborTable {
  uint16_t id;
  int16_t ping;
  uint8_t hops;
  uint16_t parent;
  int16_t meanRssi;
  int8_t rssiIndex;
  int8_t rssiValues [MAX_RSSI];
  bool rewind;
} NeighborTable;

/**
 * Table used by the LinkComponent. It contains information about
 * the node itself as well as about all of its neighbors (NeighborTable)
 **/
typedef struct PersonalTable {
	uint8_t hops;
	uint16_t parent;
	uint16_t tableIndex;
	int16_t meanParentRssi;
	NeighborTable table [MAX_NEIGHBOR];
} PersonalTable;


/**
 * Table used by the MainComponent. It allows every node to monitor 
 * all the nodes that rout through it and its neighbors.
 **/
typedef struct TreeTable {
  uint16_t id;
  int32_t conn;
  uint16_t parent;
  uint8_t hops;
  uint64_t dataId;
  uint64_t networkId;
} TreeTable;



#endif