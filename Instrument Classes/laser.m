classdef laser < instrumentType
   % NEED TO ADD SET/GET FUNCTIONS
   
   properties
      wavelength %Laser wavelength, used primarily for display
      baudRate %*********NOT REQUIRED FOR ALL LASERS, CHECK COHERENT AND 488
      portNumber
      replyInfo
      pauseTime
      waitForEquilibrium %Boolean for whether to wait until actual power matches set power
      offWhenDeleted %Should laser be turned off when object is deleted
      commands %Commands that can be sent to handshake
      handshake %Actual connection to instrument
      setPower %Current power setting
      setPowerInfo %Contains information on how to change set power
      actualPower %Current power reading 
      enabled %On/Off setting
   end
   
   methods
      function h = laser(configFileName)
         if nargin < 1
              error('Config file name required as input')
         end

         configFields = {'identifier','wavelength','baudRate','portNumber','pauseTime','waitForEquilibrium','offWhenDeleted','replyInfo'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','setPowerQuery','setPower','actualPowerQuery'};
         numericalFields = {'setPower'};%has units, conversion factor, and min/max
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);
      end

      function delete(h)
         if h.offWhenDeleted
            h = toggle(h,'off'); %#ok<NASGU>
         end
      end
      %% Internal Functions
      
      function [h,numericalData] = readNumber(h,attributeQuery)
         writeline(h.handshake,attributeQuery)
         numericalData = str2double(queryInterpretation(h));
      end
      
      function h = writeNumber(h,attribute,numericalInput)
         inputCommand = sprintf(h.commands.(attribute),numericalInput);
         writeline(h.handshake,inputCommand)
         [~] = readline(h.handshake);%OK reply to every command
      end
      
      function [h,toggleStatus] = readToggle(h,attributeQuery)         
         writeline(h.handshake,attributeQuery)
         toggleStatus = queryInterpretation(h);
      end
      
      function h = writeToggle(h,toggleCommand)
         writeline(h.handshake,toggleCommand)
         [~] = readline(h.handshake);%OK reply to every command
      end
                  
      function h = equilibrium(h,varargin)
         %Variable argument is for forcing pause time
         checkConnection(h)
         
         %Waits for set amount of time if required
         if nargin > 1 && varargin{1}
            pause(h.pauseTime)
         end

         %Don't check for equilibrium if set not to, just check the power
         if ~h.waitForEquilibrium
            h = queryActualPower(h);
            return
         end
         
         n = 0; %Counter for amount of times power is checked
         printOut('Waiting for laser equilibrium')
         
         while true %repeats until equilibrated
            %Finds current laser output
            h.actualPower = actualLaserPower(h);
            
            %Within tolerance on both sides
            if  h.actualPower <= h.setPower + h.tolerance && h.actualPower >= h.setPower - h.tolerance
               printOut('\nLaser equilibrated\n')
               break
            else
               if mod(n,2) == 0
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
      
      function h = connect(h,configName,portNumber)
         %visadevlist
         %Loads config file and checks relevant field names
         configFields = {'baudrate','replyInfo','pauseTime','powerConversionFactor','discardInitialResponse'};
         commandFields = {'toggleQuery','toggleOn','toggleOff','setPowerQuery','setPower','actualPowerQuery'};
         numericalFields = {'setPower'};
         h = loadConfig(h,configName,configFields,commandFields,numericalFields);
         
         h.handshake = serialport(sprintf('COM%d',portNumber),h.baudRate);
         configureTerminator(h.handshake,"CR")
         
         if h.replyInfo.discardFirstConnectedResponse
            %Query identification because first query gives different result from
            %later ones. Also a check on if the connection worked
            writeline(h.handshake,"*IDN?")
            [~] = queryInterpretation(h,0);
         end
         h.connected = true;
         
         h = toggle(h,'query');
         h = setLaserPower(h,'query');         
      end
      
      function h = queryActualPower(h)
         checkConnection(h)
         writeline(h.handshake,h.commands.actualPowerQuery)
         h.actualPower = queryInterpretation(h,h.replyInfo.charsDiscarded.actualPower);
         h.actualPower = h.actualPower/h.powerConversionFactor;
      end
     
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

         writeline(h.handshake,h.commands.actualPowerQuery)
         val = queryInterpretation(h);
         val = val/h.powerConversionFactor;
      end
   end    
      
   
end