function gData = pseudoGlobalData(newData)
%Stores pseudo-global data
%Used to transfer information between functions without requiring extra inputs
%Relatively high potential for error if many functions use this

%Persistent variables "persist" throughout all instances of that function
%i.e. storedData will carry over throughout every call of pseudoGlobalData but nowhere else
persistent storedData

%If input is empty, function "reads" out current values
%If input is not empty, function "writes" that to the stored data
if ~isempty(newData) 
   storedData = newData;
end

%Readout current stored data
gData = storedData;
end