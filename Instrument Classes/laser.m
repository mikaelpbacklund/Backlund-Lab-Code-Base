classdef laser < instrumentType
   
   properties
      wavelength %Laser wavelength, used primarily for display
      portNumber
      replyInfo
      pauseTime
      waitForEquilibrium %Boolean for whether to wait until actual power matches set power
      offWhenDeleted %Should laser be turned off when object is deleted
      commands %Commands that can be sent to handshake
      handshake %Actual connection to instrument
      setPowerInfo %Contains information on how to change set power
      setPower %Current power setting      
      enabled %On/Off setting
   end

   properties (SetAccess = {?laser ?instrumentType}, GetAccess = public)
      actualPower %Current power reading. UPDATES FROM INSTRUMENT EVERY TIME ACCESSED
   end
   
   methods
      function h = laser(configFileName)
         if nargin < 1
              error('Config file name required as input')
         end

         configFields = {'identifier','wavelength','uncommonProperties','pauseTime','waitForEquilibrium','offWhenDeleted'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','setPowerQuery','setPower','actualPowerQuery'};
         numericalFields = {'setPower'};%has units, conversion factor, and min/max
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);

         %Checks to make sure nested fields contain appropriate info
         mustContainField(h.uncommonProperties,{'replyInfo','connectionType'})
         if strcmpi(h.uncommonProperties.connectionType,'com')
            mustContainField(h.uncommonProperties,{'portNumber','baudRate'})
         end
         mustContainField(h.uncommonProperties.replyInfo,{'numberOfReplies','realReplyLocation','discardAfterWrite',...
            'discardFirstConnectedResponse','charsDiscarded'})
         mustContainField(h.uncommonProperties.replyInfo.charsDiscarded,{'actualPower','setPower','toggle'})
      end

      function delete(h)
         if h.offWhenDeleted
            h.enabled = false;
         end
      end
      
      %% Internal Functions
      
      function [h,numericalData] = readNumber(h,attributeQuery)
         [h,numericalData] = readInstrument(h,attributeQuery);
         numericalData = str2double(queryInterpretation(h,numericalData,true));
      end
      
      function h = writeNumber(h,attribute,numericalInput)
         inputCommand = sprintf(h.commands.(attribute),numericalInput);
         h = writeInstrument(h.handshake,inputCommand);
         if h.uncommonProperties.replyInfo.discardAfterWrite
            [~] = readline(h.handshake);%OK reply to every command
         end
         
      end
      
      function [h,toggleStatus] = readToggle(h,attributeQuery)         
         writeline(h.handshake,attributeQuery)
         toggleStatus = queryInterpretation(h);
      end
      
      function h = writeToggle(h,toggleCommand)
         writeline(h.handshake,toggleCommand)
         [~] = readline(h.handshake);%OK reply to every command
      end
                  
      function queryOutput = queryInterpretation(h,numberCharsDiscarded)
         %Requests reply from handshake repeatedly and selects "correct" reply with desired information
         %numberOfReplies, realReplyLocation, and numberCharsDiscarded must be found individually for each laser

         for ii = 1:h.replyInfo.numberOfReplies
            if ii == h.replyInfo.realReplyLocation
               queryOutput = s2c(readline(h.handshake));
            else
               [~] = readline(h.handshake);
            end
         end

         %Discards however many characters set by input
         queryOutput = queryOutput(numberCharsDiscarded+1:end);
      end
      
      %% User functions      
      
      function h = connect(h)
         %visadevlist

         if strcmpi(h.uncommonProperties.connectionType,'com')
            h.handshake = serialport(sprintf('COM%d',h.uncommonProperties.portNumber),h.uncommonProperties.baudRate);
            configureTerminator(h.handshake,"CR")
         end       
         
         if h.uncommonProperties.replyInfo.discardFirstConnectedResponse
            %Query identification because first query gives different result from
            %later ones. Also a check on if the connection worked
            writeline(h.handshake,"*IDN?")
            [~] = queryInterpretation(h,0);
         end

         h.connected = true;

         h = queryToggle(h);
         h = querySetPower(h);
         h = equilibrium(h);         
      end
     
       function h = equilibrium(h,varargin)
         %Variable argument 1 is forcing pause time
         %Variable argument 2 is giving set power to reference instead of referencing property
         checkConnection(h)
         
         %Waits for set amount of time if required
         if nargin > 1 && ~isempty(varargin{1}) && varargin{1}
            pause(h.pauseTime)
         end

         %Uses input as reference power instead of property when using the set.setPower function
         if nargin > 2 && ~isempty(varargin{2})
            referencePower = varargin{2};
         else
            referencePower = h.setPower;
         end

         %Don't check for equilibrium if set not to, just check the power
         if ~h.waitForEquilibrium
            [~] = h.actualPower;%update actual power by attempted access
            return
         end
         
         n = 0; %Counter for amount of times power is checked
         printOut('Waiting for laser equilibrium')
         
         while true %repeats until equilibrated

            %Queries actual power and stores as "currentPower"
            currentPower = h.actualPower;
            
            %Within tolerance on both sides
            if  currentPower <= referencePower + h.tolerance && currentPower >= referencePower - h.tolerance
               printOut('\nLaser equilibrated\n')
               break
            else
               
               if mod(n,2) == 0 %prints "." every half second
                  printOut('.')
               end
               n = n+1;
               
               if n > 60 %Laser shouldn't take more than 15 seconds to equilibrate
                  printOut('\nEquilibrium not established (check tolerance setting). Continuing...\n')
                  return
               end
               
               pause(.25) 
            end
         end
       end

       %% Set/Get functions
      function set.setPower(h,val)
         %Writes number to laser then runs equilibrium
         [h,newVal] = writeNumberProtocol(h,'setPower',val);         
         h = equilibrium(h,true); 
         h.setPower = newVal;
      end

      function set.enabled(h,val)
         [h,foundState] = writeToggleProtocol(h,val);          
         h = equilibrium(h,true);
         h.enabled = foundState;
      end

      function val = get.actualPower(h)
         %If not connected, give empty output
         if ~isfield(h,'connected') || isempty(h.connected) || ~h.connected
            val = [];
            return
         end
 
         writeInstrument(h,h.commands.actualPowerQuery)
         val = queryInterpretation(h);
         val = val/h.powerConversionFactor;
      end
   end    
      
   
end