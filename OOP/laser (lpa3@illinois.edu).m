classdef laser < instrumentType
   %coherentLaser and lighthousePhotonicsLaser both have this as a
   %superclass
   properties
      wavelength
      baudrate
      realReplyNumber
      responseNCharsRemoved
      pauseTime
      tolerance
      waitForEquilibrium = false;
      offWhenDeleted = false;
      commands
      handshake
      powerConversionFactor 
      setPower %Current power setting
      actualPower %Current power reading 
      enabled %On/Off setting
   end
   
   methods
      function h = laser(wavelength)
%          if nargin == 1
%             checkPort(h)
%          end
         h.wavelength = wavelength;
         switch wavelength
            case {488,561}
               h.baudrate = 19200;
               h.realReplyNumber = 2;
               h.pauseTime = 2;
               h.powerConversionFactor = 1;
               h.commands.toggleQuery = "?l";
               h.commands.toggleOn = "l=1";
               h.commands.toggleOff = "l=0";
               h.commands.setPowerQuery = "?SP";
               h.commands.setLaserPower = "P=%g";
               h.commands.actualPowerQuery = "?P";
            case 640
               h.baudrate = 19200;
               h.realReplyNumber = 1;
               h.pauseTime = 3;
               h.powerConversionFactor = 1e-3;
               h.commands.toggleQuery = "source:am:state?";
               h.commands.toggleOn = "source:am:state ON";
               h.commands.toggleOff = "source:am:state OFF";
               h.commands.setPowerQuery = "source:power:level:immediate:amplitude?";
               h.commands.setLaserPower = "source:power:level:immediate:amplitude %g";
               h.commands.actualPowerQuery = "source:power:level?";
         end
      end
      
      function h = connect(h,configName,portNumber)
         %visadevlist
         
         %Loads config file and checks relevant field names
         configFields = {'baudrate','realReplyNumber','pauseTime','powerConversionFactor','discardInitialResponse'};
         commandFields = {'toggleQuery','toggleOn','toggleOff','setPowerQuery','setPower','actualPowerQuery'};
         numericalFields = {'setPower'};
         h = loadConfig(h,configName,configFields,commandFields,numericalFields);
         
         h.handshake = serialport(sprintf('COM%d',portNumber),h.baudrate);
         configureTerminator(h.handshake,"CR")
         
         if h.discardInitialResponse
            %Query identification because first query gives different result from
            %later ones. Also a check on if the connection worked
            writeline(h.handshake,"*IDN?")
            [~] = readline(h.handshake);
            [~] = readline(h.handshake);%Replies OK after every read
         end
         h.connected = true;
         
         h = toggle(h,'query');
         h = setLaserPower(h,'query');         
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
                  
      function h = equilibrium(h)
         checkConnection(h)
         
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
      
      function queryOutput = queryInterpretation(h)
         if h.realReplyNumber == 1
            queryOutput = convertStringsToChars(readline(h.handshake));
            [~] = readline(h.handshake);
         else
            [~] = readline(h.handshake);
            queryOutput = convertStringsToChars(readline(h.handshake));            
         end
         queryOutput = queryOutput(2:end);
      end
      
      %% User functions      
      
      function h = queryActualPower(h)
         checkConnection(h)
         writeline(h.handshake,h.commands.actualPowerQuery)
         h.actualPower = queryInterpretation(h);
         h.actualPower = h.actualPower/h.powerConversionFactor;
      end
      
      function h = querySetPower(h)
         h = writeNumberProtocol(h,'setPower','query');
      end
      
      function h = setSetPower(h,inputSetPower)
         %Strange function name because you are setting the "set power"
         %property of the laser
         mustBeNumeric(inputSetPower)
         h = writeNumberProtocol(h,'setPower',inputSetPower);
         pause(h.pauseTime)
         h = equilibrium(h);
      end
      
      function h = queryToggle(h)
         h = writeToggleProtocol(h,'query');         
      end
      
      function h = toggle(h)
         h = writeToggleProtocol(h,setState);
         pause(h.pauseTime)
         h = equilibrium(h);
      end
      
   end
   
   methods (Static)
      
      function portNumber = checkPort
         b = msgbox('Turn off/disconnect laser power supply','Turn off laser');         
         while isvalid(b)
            pause(1)
         end
         
         numList = num2cell(serialportlist);
         numList = cellfun(@(a)convertStringsToChars(a),numList,'UniformOutput',false);
         numList = str2double(cellfun(@(a)a(4:end),numList,'UniformOutput',false));
         
         b = msgbox('Turn on/reconnect laser power supply','Turn on laser');
         while isvalid(b)
            pause(1)
         end
         
         numList2 = num2cell(serialportlist);
         numList2 = cellfun(@(a)convertStringsToChars(a),numList2,'UniformOutput',false);
         numList2 = str2double(cellfun(@(a)a(4:end),numList2,'UniformOutput',false));
         
         portNumber = numList2(~ismember(numList2,numList));
         fprintf('Laser port: %d\n',portNumber)
      end
   end
   
end