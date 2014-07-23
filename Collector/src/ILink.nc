#include "Table.h"

/**
 * Interface that connects the routing information obtained by the LinkComponent
 * to the MainComponent, which uses the routing information.
 */
interface ILink {	
	event void readDone(uint16_t newParent, uint8_t newHops);
	
	event void addChild(uint16_t children);
	
	event void addNeighbor(uint16_t neighbor);
	
	event void sendRssi(int16_t rssi);
	
	command void updateData();
}