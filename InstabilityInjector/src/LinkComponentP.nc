#include "Table.h"
#include "Period.h"
#include "Msg.h"
#ifdef PLATFORM_TELOSB
#include "printf.h"
#endif

module LinkComponentP @safe() {
	uses interface Boot;
	uses interface Timer<TMilli> as UpdateTimer;
	uses interface Timer<TMilli> as PingTimer;
	uses interface Timer<TMilli> as RssiTimer;
	uses interface Timer<TMilli> as RandomWait;
	uses interface Packet;
	uses interface AMSend;
	uses interface Receive;
	uses interface SplitControl;
	uses interface Random;
	uses interface CC2420Packet;
	
	provides interface ILink;
}

implementation {
	bool busy = FALSE;
	message_t message;
	PersonalTable pt;
	
	void broadcastPingMsg();
	void updateFreshness();
	void updateTableEntry(uint16_t id, uint8_t hops, uint16_t parent);
	uint16_t getBestHopAndRssiParent();
	uint8_t getMinHop();
	void calculateMeanRssi();
	void storeRssiValue(uint16_t id, int8_t rssiValue);
	void printfTable();
	
	event void Boot.booted() {
		if(TOS_NODE_ID == SINK_ID) {
			pt.hops = 0;
			pt.parent = 0;
		}
		else {
			pt.parent = DUMMY;
			pt.hops = DUMMY;
		}
		pt.tableIndex = 0;
		call SplitControl.start();
	}
	
	event void SplitControl.stopDone(error_t error) {}

	/***
	 * Overview of the timers used:
	 *  + UpdateTimer - used for periodic decaying of the freshness of the neighbor table entries.
	 *  + PingTimer - used for periodic broadcast such that the neighbor tables can be built and later 
	 * 				  the freshness of the entries can be updated. If nodes are disconnected from the
	 *     			  sink they still can construct neighbor tables based on the messages broadcasted 
	 * 				  this timer.
	 *  + RssiTimer - whenever it fires the mean RSSI for each neighbor is computed.
	 **/
	event void SplitControl.startDone(error_t error) {
		if (error == SUCCESS) {
			call UpdateTimer.startPeriodic(UPDATE_PERIOD);
			call PingTimer.startPeriodic(PING_PERIOD);
			call RssiTimer.startPeriodic(RSSI_PERIOD);
		}
		else {
			call SplitControl.start();
		}
	}
	
	event void UpdateTimer.fired() {
		updateFreshness();
	}
	
	event void PingTimer.fired() {
		broadcastPingMsg();
	}
		
	/**periodically compute the mean RSSI value for each neighbor and store it in the personal table.**/
	event void RssiTimer.fired() {
		uint8_t index = 0;

		calculateMeanRssi();
		
		for(index = 0; index < pt.tableIndex; index++) {
			if(pt.table[index].id == pt.parent) {
				signal ILink.sendRssi(pt.table[index].meanRssi);	
			}
		}
		
		if(TOS_NODE_ID == SINK_ID) {
			signal ILink.sendRssi(0);	
		}
	}
	
	event void RandomWait.fired() {
		if (call AMSend.send(AM_BROADCAST_ADDR, &message, sizeof(PingMsg)) == SUCCESS) {
				busy = TRUE;
		}
	}

	/**Three types of messages exist: PingMsg**/
	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len) {
		if(len == sizeof(PingMsg)) {
			PingMsg* pm = (PingMsg*)payload;	
			updateTableEntry(pm->id, pm->hop, pm->parent);
			storeRssiValue(pm->id, call CC2420Packet.getRssi(msg));
			if(TOS_NODE_ID != SINK_ID) {
				getBestHopAndRssiParent();
			}
		}
		return msg;
	}
	
	/**The sendDone for the quality messages is important for recording the acknowledged messages.**/
	event void AMSend.sendDone(message_t* msg, error_t error) {
		if (&message == msg) {
			busy = FALSE;	
		}
		
		
	}

	/**broadcasting ping messages used for building the neighbor tables.**/
	void broadcastPingMsg() {
		if (!busy) {
			PingMsg* pm = (PingMsg*)(call Packet.getPayload(&message, sizeof (PingMsg)));
			pm->id = TOS_NODE_ID;
			pm->hop = pt.hops;
			pm->parent = pt.parent;
			
			//wait random time approximately 1 - 111 + 5 * id milliseconds
			call RandomWait.startOneShot(call Random.rand16() / 600 + 5 * TOS_NODE_ID);
		}
	}
	
	
	/**The freshness and connectivity values of the neighbors are decayed, if 0 the neighbor is removed
	 * If the connectivity hits 0 the node claims it has DUMMY as hop and parent.**/
	void updateFreshness() {
		uint16_t index;
		
		//decay freshness
		for(index = 0; index < pt.tableIndex; index++) {
			pt.table[index].ping = pt.table[index].ping - UPDATE_PERIOD;
		}
		
		//swapping last neighbor with the removed one and all of its data
		for(index = 0; index < pt.tableIndex; index++) {
			if(pt.table[index].ping <= 0) {
	
			pt.table[index].id = pt.table[pt.tableIndex - 1].id;
			pt.table[index].ping = pt.table[pt.tableIndex - 1].ping;
			pt.table[index].hops = pt.table[pt.tableIndex - 1].hops;	
			pt.table[index].parent = pt.table[pt.tableIndex - 1].parent;
			pt.table[index].meanRssi = pt.table[pt.tableIndex - 1].meanRssi;
			pt.table[index].rssiIndex = pt.table[pt.tableIndex - 1].rssiIndex;
			pt.table[index].rewind = pt.table[pt.tableIndex - 1].rewind;
			strncpy(pt.table[pt.tableIndex - 1].rssiValues, pt.table[index].rssiValues, MAX_RSSI);

			pt.tableIndex--;
	
			index = 0;
			}
		}
	}
	
	
	/***
	 * Update the freshness of the node that sent the message
	 **/
	void updateTableEntry(uint16_t id, uint8_t hops, uint16_t parent) {
		uint16_t index = 0;
		bool idAlreadyInTable = FALSE;
 		
		for(index = 0; index < pt.tableIndex; index++) { //ping messages
			if(pt.table[index].id == id) {
				pt.table[index].ping = MAX_PING;
				pt.table[index].hops = hops;
				
				pt.table[index].parent = parent;
				idAlreadyInTable = TRUE;
				break;
			}
		}
		
		if(!idAlreadyInTable) {
			pt.table[pt.tableIndex].id = id;
			pt.table[pt.tableIndex].ping = MAX_PING;
			pt.table[pt.tableIndex].hops = hops;
			pt.table[index].parent = parent;
			
			pt.tableIndex++;
		}
	}
	
	
	/**
	 * In order to calculate a more stable RSSI value for a given neighbor, we maintain 
	 * an RSSI array of size 20 for each neighbor to which newly recorded RSSI values are
	 * stored. After storing 20 values we go back to index 0 and start all over by 
	 * replacing the oldest values with new ones. These 20 values are used to compute the
	 * RSSI mean for each neighbor when needed.  
	 **/
	void storeRssiValue(uint16_t id, int8_t rssiValue) {
		uint8_t index = 0;
		
		for(index = 0; index < pt.tableIndex; index++) {
			if(pt.table[index].id == id) {
				if(pt.table[index].rssiIndex == MAX_RSSI) {
					pt.table[index].rssiIndex = 0;
					pt.table[index].rewind = TRUE;
				}
				
				pt.table[index].rssiValues[pt.table[index].rssiIndex] = rssiValue;
				pt.table[index].rssiIndex++;
				
				break;
			}
		}
	}
	
	
	/**
	 * Obtains the neighbor with the min. hop to the sink which has also the greatest 
	 * mean RSSI value. If multiple such neighbors are available, the first occurrence 
	 * is taken. This is an extension of the min. hop technique of obtaining a routing 
	 * parent.
	 **/
	uint16_t getBestHopAndRssiParent() {
		uint8_t minHop = getMinHop();
		int16_t minRssi = -200;
		uint8_t savedIndex;
		uint8_t index = 0;

		if(TOS_NODE_ID == SINK_ID) {
			return 0;
		}
		
		if(minHop == DUMMY) {
			signal ILink.readDone(DUMMY, DUMMY);
			return DUMMY;
		}
		
		
		for(index = 0; index < pt.tableIndex; index++) {
			if(pt.table[index].hops == minHop) {
				if(pt.table[index].meanRssi > minRssi) {
					minRssi = pt.table[index].meanRssi;
					savedIndex = index;
				}
			}
		}
		
		if(pt.table[savedIndex].id != pt.parent) {
//			if(rssiChangeIsBig(minRssi)) {
				pt.parent = pt.table[savedIndex].id;
				pt.hops = minHop + 1;
//			}
			signal ILink.readDone(pt.parent, pt.hops);
		}
		return pt.parent;	
	}
	
	/**
	 * TODO: still not implemented fully. This method should avoid a node
	 * switching its parents because small deviation in the RSSI. Only an
	 * increase in RSSI by a given threshold (10%) should be taken into
	 * consideration. 
	 */
	bool rssiChangeIsBig(int16_t newRssi) {
		int16_t tempNewRssi = newRssi;
		int16_t tempOldRssi = pt.meanParentRssi;
		
		if(tempNewRssi < 0) {
			tempNewRssi = tempNewRssi * -1;
		}
		
		if(tempOldRssi < 0) {
			tempOldRssi = tempOldRssi * -1;
		}
		
		if((tempNewRssi - tempOldRssi) > 5) {
			return TRUE;
		}
		
		if((tempNewRssi - tempOldRssi) < -5) {
			return TRUE;
		}
		
		return FALSE;
	}
	
	
	/**
	 * Auxiliary function for finding the neighbor with the min. hop count to the sink. 
	 */
	uint8_t getMinHop() {
		uint16_t index = 0;
		uint8_t minHop = DUMMY;
 
		for(index = 0; index < pt.tableIndex; index++) {
			if(pt.table[index].hops < minHop) {
				minHop = pt.table[index].hops;		
			}
		}
		return minHop;
	}
	
	
	/**
	 * Computes the mean float for all the neighbors and adds the computed value 
	 * to the appropriate PersonalTable entry for later usage. 
	 */
	void calculateMeanRssi() {
		int8_t index = 0;
		
		for(index = 0; index < pt.tableIndex; index++) {
			int16_t sum = 0;
			uint8_t rsIndex = 0;
			uint8_t lastIndex = 0;
			
			if(pt.table[index].rewind == TRUE) {
				lastIndex = MAX_RSSI;
			}
			else {
				lastIndex = pt.table[index].rssiIndex;
			}
			
			for(rsIndex = 0; rsIndex < lastIndex; rsIndex++) {
				sum += pt.table[index].rssiValues[rsIndex];
			}
	
			pt.table[index].meanRssi = sum / lastIndex;
		}		
	}
	
	/**Periodically print out the parameters of the PersonalTable structure.**/
	void printfTable() {
		uint16_t index = 0;
	
		#ifdef PLATFORM_TELOSB
		printf("============= neighbor table of node: %d ============= \n", TOS_NODE_ID);
		printfflush();
		#endif

		for(index = 0; index < pt.tableIndex; index++) {
			#ifdef PLATFORM_TELOSB
			printf("| %d . | id: %d | ping: %d |  hops: %d | parent: %d |\n", 
			index, pt.table[index].id, pt.table[index].ping, pt.table[index].hops, pt.table[index].parent); 
			printf("| meanRssi: %d | rssiIndex: %d | rewind %d | \n", 
			pt.table[index].meanRssi, pt.table[index].rssiIndex, pt.table[index].rewind);
			printf("\n");
			printfflush();
			#endif
		}
		
		#ifdef PLATFORM_TELOSB
		printf("| parent %d | hops %d | \n", pt.parent, pt.hops);
		printfflush();
		#endif
		
		#ifdef PLATFORM_TELOSB
		printf("====================== END ====================== \n \n");
		printfflush();
		#endif
	}

	/**Sends information to the MainComponent about the routing children of the current node.**/
	command void ILink.updateData(){
		uint8_t index = 0;
		for(index = 0; index < pt.tableIndex; index++) {
			if(pt.table[index].parent == TOS_NODE_ID) {
				signal ILink.addChild(pt.table[index].id);
			}
			signal ILink.addNeighbor(pt.table[index].id);
		}
	}
}