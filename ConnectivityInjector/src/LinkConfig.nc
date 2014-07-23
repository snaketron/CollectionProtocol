configuration LinkConfig {
	provides interface ILink;
}

implementation {
  components MainC, LinkComponentP, ActiveMessageC;
  components new AMSenderC(AM_COLLECTOR);
  components new AMReceiverC(AM_COLLECTOR);
  
  components new TimerMilliC() as UpdateTimer;
  components new TimerMilliC() as PingTimer;
  components new TimerMilliC() as RssiTimer;
  components new TimerMilliC() as RandomWait;
  
  #ifdef PLATFORM_TELOSB
  components SerialPrintfC;
  #endif
  
  components RandomC;
  
  components CC2420PacketC;
  
  LinkComponentP -> MainC.Boot;

  LinkComponentP.UpdateTimer -> UpdateTimer;
  LinkComponentP.PingTimer -> PingTimer;
  LinkComponentP.RssiTimer -> RssiTimer;
  LinkComponentP.RandomWait -> RandomWait;
  
  LinkComponentP.AMSend -> AMSenderC;
  LinkComponentP.Packet -> AMSenderC;
  LinkComponentP.Receive -> AMReceiverC;
  
  LinkComponentP.SplitControl -> ActiveMessageC;
  
  LinkComponentP.Random -> RandomC;
  
  ILink = LinkComponentP;
  
  LinkComponentP.CC2420Packet -> CC2420PacketC;
}