configuration MainConfig {
	
}

implementation {
  components MainC, MainComponentC, LedsC, ActiveMessageC;
  components new AMSenderC(AM_COLLECTOR);
  components new AMReceiverC(AM_COLLECTOR);
  
  components new TimerMilliC() as SensingTimer;
  components new TimerMilliC() as SendingTimer;
  components new TimerMilliC() as NetworkTimer;
  components new TimerMilliC() as UpdateTimer;
  components new TimerMilliC() as RandomWait;
  
  components new SensirionSht11C() as Sensor;
  components new HamamatsuS1087ParC() as LightSensor;
  components new Msp430InternalVoltageC() as VoltageSensor;
   
  #ifdef PLATFORM_TELOSB
  components SerialPrintfC;
  #endif
  components RandomC;
  components LinkConfig;
  
  components new QueueC(message_t * , 10) as Queue;

  MainComponentC -> MainC.Boot;
  MainComponentC.Leds -> LedsC;

  MainComponentC.SensingTimer -> SensingTimer;
  MainComponentC.SendingTimer -> SendingTimer;
  MainComponentC.NetworkTimer -> NetworkTimer;
  MainComponentC.UpdateTimer -> UpdateTimer;
  MainComponentC.RandomWait -> RandomWait;
  
  MainComponentC.AMSend -> AMSenderC;
  MainComponentC.Packet -> AMSenderC;
  MainComponentC.Receive -> AMReceiverC;
  MainComponentC.Acks -> AMSenderC;
  
  MainComponentC.SplitControl -> ActiveMessageC;
  
  MainComponentC.ReadHumidity -> Sensor.Humidity;
  MainComponentC.ReadTemperature -> Sensor.Temperature;
  MainComponentC.ReadLight -> LightSensor.Read;
  MainComponentC.ReadVoltage -> VoltageSensor.Read;
  
  MainComponentC.Random -> RandomC;
  
  MainComponentC.MsgBuffer -> Queue;
  
  MainComponentC.ILink -> LinkConfig.ILink;
}