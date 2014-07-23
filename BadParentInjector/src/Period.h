#ifndef PERIOD_H
#define PERIOD_H

enum {  
  /**no data or network msg from a node in 20 sec => node is disconnected.**/
  MAX_CONNECTIVITY = 20000,
  
  /**no ping msg from a neighbor in 15 sec => node is removed from neighbor table.**/
  MAX_PING = 15000,
  
  /**if of the sink.**/
  SINK_ID = 2,
  
  /**ping message period**/
  PING_PERIOD = 3000,
  
  /**update period, used in various timing functions.**/
  UPDATE_PERIOD = 1000,
  
  /**sensing period.**/
  SENSE_PERIOD = 2500,
  
  /**data msg period.**/
  SEND_PERIOD = 2090,
  
  /**network message period.**/
  NETWORK_PERIOD = 9050,
  
  /**rssi update period.**/
  RSSI_PERIOD = 7000 
};

#endif
