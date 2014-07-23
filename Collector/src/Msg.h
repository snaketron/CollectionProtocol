#include "Table.h"

#ifndef MESSAGES_H
#define MESSAGES_H

enum {
	AM_COLLECTOR = 6,
};

typedef nx_struct PingMsg {
	nx_uint16_t id;
	nx_uint8_t hop;
	nx_uint16_t parent;
} PingMsg;

typedef nx_struct DataMsg {
	nx_uint64_t msgId;
	nx_uint16_t origin;
	nx_uint16_t sourceId;
	nx_uint16_t targetId;
	nx_uint16_t humidity;
	nx_uint16_t temperature;
	nx_uint16_t light;
	nx_uint16_t voltage;
} DataMsg;


typedef nx_struct LocalInfo {
	nx_uint16_t children [MAX_NEIGHBOR];
	nx_uint8_t childrenPackets [MAX_NEIGHBOR];
	nx_uint8_t childrenIndex;
	nx_uint16_t neighbors [MAX_NEIGHBOR];
	nx_uint8_t neighborIndex;
} LocalInfo;


typedef nx_struct NetworkMsg {
	nx_uint64_t msgId;
	nx_uint16_t origin;
	nx_uint16_t originParent;
	nx_uint16_t sourceId;
	nx_uint16_t targetId;
	nx_uint8_t hops;
	nx_uint16_t connectedSince;
	nx_int16_t meanRSSI;
	LocalInfo info;
} NetworkMsg; 

#endif /* MESSAGE_H */
