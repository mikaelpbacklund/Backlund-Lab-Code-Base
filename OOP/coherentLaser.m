classdef coherentLaser < laser
   %Coherent and lighthouse photonics have sufficiently different
   %interactions between matlab and the lasers themselves that it is better
   %just to split off these internal functions into two different classes
   %and have the user functions be in a superclass
   methods
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
      
   end
end