function [binaryOutput] = PBDec2Bin(base10input)
%Convert base 10 number to binary output with the correct number of leading
%zeros based on the number of channels in the pulse blaster

%PBDec2Bin v1.0 5/26/22

global master

InitializationCheck('PB')

nchan = master.PB.nchannels;

%If the length of the binary value is not equal to the number of channels,
%add leading zeros.
valbin = dec2bin(base10input);
lvalbin = length(valbin);
if lvalbin ~= nchan
   binaryOutput(1:nchan-lvalbin) = '0';
   master.test.binaryOutput = binaryOutput;
   master.test.base10input = base10input;
   master.test.valbin = valbin;
   binaryOutput(1+nchan-lvalbin:nchan) = valbin;
else
   binaryOutput = valbin;
end

end