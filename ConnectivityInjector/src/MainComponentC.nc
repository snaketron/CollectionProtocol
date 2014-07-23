#include "Msg.h"
#include "Table.h"
#include "Period.h"
#ifdef PLATFORM_TELOSB
#include "printf.h"
#endif

module MainComponentC @safe() {
	uses interface Boot;
	uses interface Timer<TMilli> as SensingTimer;
	uses interface Timer<TMilli> as SendingTimer;
	uses interface Timer<TMilli> as NetworkTimer;
	uses interface Timer<TMilli> as UpdateTimer;
	uses interface Timer<TMilli> as RandomWait;
	uses interface Timer<TMilli> as Connectivity;
	uses interface Timer<TMilli> as Delay;
	uses interface Leds;
	uses interface Packet;
	uses interface AMSend;
	uses interface Receive;
	uses interface SplitControl;
	uses interface Read<uint16_t> as ReadHumidity;
	uses interface Read<uint16_t> as ReadTemperature;
	uses interface Read<uint16_t> as ReadVoltage;
	uses interface Read<uint16_t> as ReadLight;
	uses interface Random;
	uses interface PacketAcknowledgements as Acks;

	uses interface ILink;
	
	uses interface Queue<message_t*> as MsgBuffer;
}

implementation {
	bool busy = FALSE;
	
	//separate packet buffers for sending and forwarding
	message_t dataMsg;
	message_t forwardDataMsg;
	message_t netMsg;
	message_t forwardNetMsg;
	
	//initial state of the nodes. These variables are updated by the LinkComponent	
	uint16_t parent = DUMMY;
	uint8_t hops = DUMMY;
  	int16_t rssi;
	
	//information about all the nodes that route trough this node
	TreeTable treeTable [MAX_NODES];
	uint8_t treeIndex = 0;
	
	//information about all the neighbors of this node
	LocalInfo info;
	uint16_t connectedSince = 0;

	//const
  	uint16_t div = 1000;
  	
  	//variables for keeping the sensed information
	uint16_t humidity, temperature, light, voltage = 0;
	bool h, t, l, v = FALSE;
	
	//data and network message identifiers (initial value)
	uint64_t dataId = 1;
	uint64_t networkId = 1;
	
	bool disconnected = FALSE;
	
	//method declarations
	task void sendDataMessage();
	task void sendNetworkMessage();
	task void resendBufferedMessages();
	void updateConnectivity();
	void updateChildTable(uint16_t sourceId, uint16_t originId, uint16_t targetId);
	void processAndForwardDataMsg(DataMsg * msg);
	void processAndForwardNetworkMsg(NetworkMsg * msg);
	void printNetworkMsg(NetworkMsg * msg);
	bool dataIdIsValid(uint16_t msgMoteId, uint64_t msgDataId);
	bool networkIdIsValid(uint16_t msgMoteId, uint64_t msgNetworkId, uint16_t msgOriginParent, uint8_t msgHops);
	
	
	event void Boot.booted() {
		call SplitControl.start();
	}
	
	
	event void SplitControl.stopDone(error_t error){}


	event void SplitControl.startDone(error_t error) {
		if (error == SUCCESS) {
			if(TOS_NODE_ID != SINK_ID) {
				//every node but the sink senses and sends data messages
				call SensingTimer.startPeriodic(SENSE_PERIOD);
				call SendingTimer.startPeriodic(SEND_PERIOD);
			}
			
			call UpdateTimer.startPeriodic(UPDATE_PERIOD);
			call NetworkTimer.startPeriodic(NETWORK_PERIOD);
			call Delay.startOneShot(15000);
		}
		else {
			call SplitControl.start();
		}
	}
	
	
	/**On fire, sense humidity, temperature, light and battery. (all nodes but sink)**/
	event void SensingTimer.fired() {
		call ReadHumidity.read();
		call ReadTemperature.read();
		call ReadLight.read();
		call ReadVoltage.read();
	}
	
	
	/**Only if all 4 properties have been sensed, send a data message. **/
	event void SendingTimer.fired() {
		if(!disconnected) {
			if((h == TRUE) & (t == TRUE) & (l == TRUE) & (v == TRUE)) {
				post sendDataMessage();
			}
		}
	}
	
	
	/**On fire, send network message. (all nodes)**/
	event void NetworkTimer.fired() {
		if(!disconnected) {
			post sendNetworkMessage();
		}
	}
	
	
	/**
	 * update neighborhood connectivity information for all nodes that 
	 * rout through this node. Increment the connectedSince variable
	 * which is set to 0 whenever a node changes its parent. 
	 **/
	event void UpdateTimer.fired() {
		updateConnectivity();	
		connectedSince = connectedSince + 1;
	}
	
	
	/**
	 * If no acknowledgment is received this timer is called to fire at a 
	 * random time. On fire, try to transmit all the messages in the buffer.
	 **/
	event void RandomWait.fired() {
		post resendBufferedMessages();
	}
	
	
	event void Connectivity.fired() {
		if(disconnected) {
			disconnected = FALSE;	
		}
		else {
			disconnected = TRUE;
		}
	}
	
	
	event void Delay.fired() {
		call Connectivity.startPeriodic(60000);
	}
	
	
	/**
	 * Retransmit all the messages in the buffer. 
	 **/
	task void resendBufferedMessages() {
		uint8_t index = 0;
		uint8_t bufferSize = call MsgBuffer.size();
		
		for(index = 0; index < bufferSize; index++) {
			message_t * msg = call MsgBuffer.dequeue();
			
			if(call Packet.payloadLength(msg) == sizeof(NetworkMsg)) {
				if(call AMSend.send(parent, msg, sizeof(NetworkMsg)) == SUCCESS) {
					busy = TRUE;
				}
			}
			else if(call Packet.payloadLength(msg) == sizeof(DataMsg)) {
				if(call AMSend.send(parent, msg, sizeof(DataMsg)) == SUCCESS) {
					busy = TRUE;
				}
			}
		}
	}
	
	
	/**
	 * Check for acknowledgment. If no ack, call the RandomWait timer to fire.
	 * Set busy to FALSE to allow radio to operate in the meantime. 
	 **/
	event void AMSend.sendDone(message_t* msg, error_t error) {
		bool acked = call Acks.wasAcked(msg);
		if(!acked) {
			call MsgBuffer.enqueue(msg);			
			call RandomWait.startOneShot(call Random.rand16() / div + 5 * TOS_NODE_ID);
		}
		busy = FALSE;
	}
	
	
	/**
	 * If the sink is the receptor of the data message, print the message. Else forward
	 * the message toward the parent of this node.
	 **/
	void processAndForwardDataMsg(DataMsg * msg) {	
		if(TOS_NODE_ID == SINK_ID) {
			#ifdef PLATFORM_TELOSB
			printf("data | %d; %d; %d; %d; %d; %llu ", msg->origin, msg->humidity, msg->temperature, 
					msg->light, msg->voltage, msg->msgId);
			printf("\n");
			printfflush();
			#endif
		}
		else {
			if(!busy) {
				if(msg->targetId == TOS_NODE_ID) {
					error_t er;
					
					DataMsg* dm = (DataMsg*)(call Packet.getPayload(&forwardDataMsg, sizeof (DataMsg)));
					dm->msgId = msg->msgId;
					dm->origin = msg->origin;
					dm->humidity = msg->humidity;
					dm->sourceId = TOS_NODE_ID;
					dm->targetId = parent;
					dm->humidity = dm->humidity;
					dm->temperature = dm->temperature;
					dm->light = dm->light;
					dm->voltage = dm->voltage;
	
					call Acks.requestAck(&forwardDataMsg);
					er = call AMSend.send(dm->targetId, &forwardDataMsg, sizeof(DataMsg));
					if (er == SUCCESS) {
						busy = TRUE;
					}
				}
			}
		}
	}


	/**
	 * If the sink is the receptor of the network message, print the message. Else 
	 * forward the message toward the parent of this node.
	 **/
	void processAndForwardNetworkMsg(NetworkMsg * msg) {
		if(TOS_NODE_ID == SINK_ID) {
			printNetworkMsg(msg);
		}
		else {
			if(!busy) {
				if(msg->targetId == TOS_NODE_ID) {
					NetworkMsg* nm = (NetworkMsg*)(call Packet.getPayload(&forwardNetMsg, sizeof (NetworkMsg)));
					nm->msgId = msg->msgId;
					nm->origin = msg->origin; 
					nm->sourceId = TOS_NODE_ID;
					nm->targetId = parent;
					nm->originParent = msg->originParent;
					nm->hops = msg->hops;
					nm->info = msg->info;
					nm->connectedSince = msg->connectedSince;
					nm->meanRSSI = msg->meanRSSI;
	
					call Acks.requestAck(&forwardNetMsg);
					if (call AMSend.send(parent, &forwardNetMsg, sizeof(NetworkMsg)) == SUCCESS) {
						busy = TRUE;
					}
				}
			}
		}
	}


	/**
	 * Upon message reception, check message type and relay it to the correct function.
	 * Before relaying check if the message id of the message is valid (higher than the
	 * one received previously from that node => this avoid duplicates in case no ack is 
	 * received but the message has been transmitted correctly) 
	 **/
	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len) {
		if(len == sizeof(DataMsg)) {
			DataMsg* dm = (DataMsg*)payload;
			
			if(dataIdIsValid(dm->origin, dm->msgId)) {
				processAndForwardDataMsg(dm);
				updateChildTable(dm->sourceId, dm->origin, dm->targetId);
			}
		}
		else if(len == sizeof(NetworkMsg)) {
			NetworkMsg* nm = (NetworkMsg*)payload;
			
			if(networkIdIsValid(nm->origin, nm->msgId, nm->originParent, nm->hops)) {
				processAndForwardNetworkMsg(nm);
			}
		}
		return msg;
	}


	/**
	 * Sending data messages where the sensed information is stored. If this node
	 * has no routing information such as a routing parent the sending won't happen. 
	 **/
	task void sendDataMessage() {
		error_t er;
		
		DataMsg* dm = (DataMsg*)(call Packet.getPayload(&dataMsg, sizeof (DataMsg)));
		dm->msgId = dataId;
		dm->origin = TOS_NODE_ID;
		dm->sourceId = TOS_NODE_ID;
		dm->targetId = parent;
		dm->humidity = humidity;
		dm->temperature = temperature;
		dm->light = light;
		dm->voltage = voltage;
		
		if(parent != DUMMY) {
			call Acks.requestAck(&dataMsg);
			er = call AMSend.send(parent, &dataMsg, sizeof(DataMsg)); 
			if(er == SUCCESS) {
				busy = TRUE;
				dataId++;
				
				h = FALSE;
				t = FALSE;
				l = FALSE;
				v = FALSE;
			}
		}
	}
	
	
	/**
	 * Sending network messages. If the current node is the sink, only print the content
	 * of the network message. Otherwise send the message to the routing parent.
	 **/
	task void sendNetworkMessage() {
		NetworkMsg* nm = (NetworkMsg*)(call Packet.getPayload(&netMsg, sizeof (NetworkMsg)));
		nm->msgId = networkId;
		nm->origin = TOS_NODE_ID;
		nm->sourceId = TOS_NODE_ID;
		nm->targetId = parent;
		nm->originParent = parent;
		nm->hops = hops;
		nm->info = info;
		nm->connectedSince = connectedSince;
		nm->meanRSSI = rssi;
	
		if(TOS_NODE_ID == SINK_ID) {
			printNetworkMsg(nm);
			networkId++;
		}
		else {
			call Acks.requestAck(&netMsg);
			if((parent != DUMMY)&&(hops != DUMMY)) {
				if (call AMSend.send(parent, &netMsg, sizeof(NetworkMsg)) == SUCCESS) {
					busy = TRUE;
					networkId++;
				}
			}
		}
	}

	event void ReadHumidity.readDone(error_t result, uint16_t val) {
		humidity = val;
		h = TRUE;
	}

	event void ReadTemperature.readDone(error_t result, uint16_t val){
		temperature = val;
		t = TRUE;
	}
	
	
	event void ReadVoltage.readDone(error_t result, uint16_t val){
		voltage = val;
		v = TRUE;
	}
	
	
	event void ReadLight.readDone(error_t result, uint16_t val){
		light = val;
		l = TRUE;
	}
	
	
	/**
	 * An event from the LinkComponent informing MainComponent about the
	 * new routing information of the node. 
	 **/
	event void ILink.readDone(uint16_t newParent, uint8_t newHops){
		parent = newParent;
		hops = newHops;
		connectedSince = 0;
		info.childrenIndex = 0;
		info.neighborIndex = 0;
		call ILink.updateData();
	}
	
	
	/**
	 * Every second (UPDATE_PERIOD) reduce the connectivity of every node kept 
	 * in the treeTable. If the connectivity of a given mote in this table hits
	 * 0 or less, this node is considered as disconnected and is removed from the
	 * table. A network message is printed by the sink node, posing as the disconnected
	 * node, informing the application about the disconnection.
	 **/
	void updateConnectivity() {
		uint8_t index = 0;
		
		for(index = 0; index < treeIndex; index++) {
			treeTable[index].conn = treeTable[index].conn - UPDATE_PERIOD;
		}
		
		for(index = 0; index < treeIndex; index++) {
			if(treeTable[index].conn <= 0) {
				if(TOS_NODE_ID  == SINK_ID) {
					#ifdef PLATFORM_TELOSB
					printf("network | %d; %d; %d; %d; %d; %d; %d; %d; %d; | ", treeTable[index].id, 
					treeTable[index].parent, treeTable[index].hops, 0, 0, 0, 0, 0, 0);
					printf(" | ");
					printf("\n");
					printfflush();
					#endif
				}
				
				treeTable[index].id = treeTable[treeIndex - 1].id;
				treeTable[index].conn = treeTable[treeIndex - 1].conn;
				treeTable[index].parent = treeTable[treeIndex - 1].parent;
				treeTable[index].hops = treeTable[treeIndex - 1].hops;
				treeTable[index].dataId = treeTable[treeIndex - 1].dataId;
				treeTable[index].networkId = treeTable[treeIndex - 1].networkId;
				treeIndex--;
			}
		}
	}
	
	
	/**
	 * Prints network messages in a format that is interpretable by the monitoring application.
	 **/
	void printNetworkMsg(NetworkMsg * nm) {
		uint8_t index = 0;
		
		#ifdef PLATFORM_TELOSB
		printf("network | %d; %d; %d; %d; %d; %d; %d; %d; %d; | ", nm->origin, nm->originParent, nm->hops, 
				1, nm->connectedSince, nm->meanRSSI, nm->info.childrenIndex, nm->info.neighborIndex, nm->msgId);
		for(index = 0; index < nm->info.childrenIndex; index++) {
			printf("%d:%d; ", nm->info.children[index], nm->info.childrenPackets[index]);
		}
		printf(" | ");
		for(index = 0; index < nm->info.neighborIndex; index++) {
			printf("%d;", nm->info.neighbors[index]);
		}
		printf("\n");
		printfflush();
		#endif
 	}	
	
	
	/**
	 * Updates the structure info in which the routing children of this node are 
	 * store with the number of packets received from each of them between two adjecent
	 * network messages.
	 **/
	void updateChildTable(uint16_t sourceId, uint16_t originId, uint16_t targetId) {
		if(originId == sourceId) {
			uint8_t index = 0;
			for(index = 0; index < info.childrenIndex; index++) {
				if(info.children[index] == sourceId) {
					info.childrenPackets[index] = info.childrenPackets[index] + 1;
				}
			}
		}
	}
	
	
	/**
	 * Checks whether the message id of a received data message is higher than
	 * the last id stored from this node. It is also used to update the treeTable
	 * structure if a node is not already existent in it.
	 */
	bool dataIdIsValid(uint16_t msgMoteId, uint64_t msgDataId) {
		uint8_t index = 0;
		bool moteIdInTable = FALSE;
		
		for(index = 0; index < treeIndex; index++) {
			if(treeTable[index].id == msgMoteId) {
				if(msgDataId > treeTable[index].dataId) {
					treeTable[index].dataId = msgDataId;
					return TRUE;
				}
				else {
					return FALSE;
				}
			}
		}
	
		if(!moteIdInTable) {
			treeTable[treeIndex].id = msgMoteId;
			treeTable[treeIndex].dataId = msgDataId;
			treeTable[treeIndex].networkId = 0;
			treeTable[treeIndex].conn = MAX_CONNECTIVITY;
			treeIndex++;
		}
		
		return TRUE;
	}
	
	
	/**
	 * Checks whether the message id of a received network message is higher than
	 * the last id stored from this node. It is also used to update the treeTable
	 * structure if a node is not already existent in it.
	 */
	bool networkIdIsValid(uint16_t msgMoteId, uint64_t msgNetworkId, uint16_t msgOriginParent, uint8_t msgHops) {
		uint8_t index = 0;
		bool moteIdInTable = FALSE;
		
		for(index = 0; index < treeIndex; index++) {
			if(treeTable[index].id == msgMoteId) {
				if(msgNetworkId > treeTable[index].networkId) {
					treeTable[index].networkId = msgNetworkId;
					treeTable[index].conn = MAX_CONNECTIVITY;
					treeTable[index].parent = msgOriginParent; 
					treeTable[index].hops = msgHops;
					return TRUE;
				}
				else {
					return FALSE;
				}
			}
		}
	
		if(!moteIdInTable) {
			treeTable[treeIndex].id = msgMoteId;
			treeTable[treeIndex].networkId = msgNetworkId;
			treeTable[treeIndex].dataId = 0;
			treeTable[treeIndex].conn = MAX_CONNECTIVITY;
			treeTable[treeIndex].parent = msgOriginParent; 
			treeTable[treeIndex].hops = msgHops;
			treeIndex++;
		}
		
		return TRUE;
	}
	
		
	/**
	 * Event from the LinkComponent informing the node about its routing children.
	 **/
	event void ILink.addChild(uint16_t child) {
		info.children[info.childrenIndex] = child;
		info.childrenPackets[info.childrenIndex] = 0;
		info.childrenIndex = info.childrenIndex + 1;
	}
	
	
	/**
	 * Event from the LinkComponent informing the node about its routing neighbors.
	 **/
	event void ILink.addNeighbor(uint16_t neighbor) {
		info.neighbors[info.neighborIndex] = neighbor;
		info.neighborIndex = info.neighborIndex + 1;
	}


	/**
	 * Event from the LinkComponent informing the node about its mean rssi 
	 * towards its routing parent.
	 **/
	event void ILink.sendRssi(int16_t newRssi){
		rssi = newRssi;
		info.childrenIndex = 0;
		info.neighborIndex = 0;
		call ILink.updateData();
	}
}