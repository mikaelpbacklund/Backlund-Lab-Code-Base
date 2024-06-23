classdef lighthousePhotonicsLaser < laser
   methods
      
      function [h,numericalData] = readNumber(h,attributeQuery)
         writeline(h.handshake,attributeQuery)
         numericalData = str2double(queryInterpretation(h));
      end
      
      function h = writeNumber(h,attribute,numericalInput)
         inputCommand = sprintf(h.commands.(attribute),numericalInput);
         writeline(h.handshake,inputCommand)
      end
      
      function [h,toggleStatus] = readToggle(h,attributeQuery)
         writeline(h.handshake,attributeQuery)
         toggleStatus = queryInterpretation(h);
      end
      
      function h = writeToggle(h,toggleCommand)
         %If it is a query, loop checking the status?
         while true
            writeline(h.handshake,toggleCommand)
            break
         end
      end
      
      function queryOutput = queryInterpretation(h)
         %Query interpretation is annoying here because it doesn't just
         %give the answer requested, it also spits back out information
         %about the query itself (e.g. POWER=1.3)
         %At the moment, it is sufficient just to check if it contains
         %on/off/idle then find where it becomes a number if it doesn't
         
         queryOutput = convertStringsToChars(readline(h.handshake));
         if contains(queryOutput,'ON')
         elseif contains(queryOutput,'OFF')
         elseif contains(queryOutput,'IDLE')
         elseif contains(queryOutput,'POWER')
         end
         
         
         if h.realReplyNumber == 1
            queryOutput = convertStringsToChars(readline(h.handshake));
            [~] = readline(h.handshake);
         else
            [~] = readline(h.handshake);
            queryOutput = convertStringsToChars(readline(h.handshake));
         end
         queryOutput = queryOutput(2:end);
      end
   end
   
   
end