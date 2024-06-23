function convertedValue = MultiFieldConversion(inputValue)
%Converts a character array with numbers separated by commas to a matrix or
%vice versa

%MultiFieldConversion v1.1 4/20/22

%Checks if input is character array
if isa(inputValue,'char')
   
   %Finds number of commas and uses that to determine desired number of output
   %elements
   commas = find(inputValue == ',');
   nstarts = 1+length(commas);
   
   %If only one number is present, simply convert that number
   if nstarts == 1,     convertedValue = str2double(inputValue);
      
   else
      
      convertedValue = zeros(1,length(commas));
      for ii = 1:nstarts
         
         %If this is the first output element, begin at the first input element,
         %otherwise it begins one after where the last comma was
         if ii == 1
            begnum = 1;
         else
            begnum = commas(ii-1)+1;
         end
         
         %If this is the last output element, end at the last input element
         %otherwise it end one before where the current comma is
         if ii == nstarts
            endnum = length(inputValue);
         else
            endnum = commas(ii)-1;
         end
         
         %Converts input elements between start and end into doubles and adds
         %as an output element
         convertedValue(ii) = str2double(inputValue(begnum:endnum));
      end
      
   end
   
elseif isa(inputValue,'double') %Checks if input is a double which would be a single number or vector or matrix

   convertedValue = '';
   for ii = 1:length(inputValue)
      if floor(inputValue(ii)) == inputValue(ii) %Is the number an integer
         %In sets of three chars, add the number followed by a comma then a space
         charValue = sprintf('%d, ',inputValue(ii));
         %More than 5 numbers gets contracted to scientific notation
         if numel(charValue) > 7
            charValue = sprintf('%.3g, ',inputValue(ii));
         end
      else
         %Add the number in scientific notation followed by a comma then a space
         charValue = sprintf('%.3g, ',inputValue(ii));
      end
      
      
      
      %Add current character array to the end of the output
      convertedValue(end+1:end+numel(charValue)) = charValue;
   end
   
   %Delete the last comma and space
   convertedValue(end-1:end) = [];
   
else
   error('MultiFieldConversion input must be a character array or double');
   
end

end
