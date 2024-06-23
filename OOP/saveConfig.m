function saveConfig(savePath,generalFields,generalValues,varargin)
%Saves the config values within as a .mat file

%This function could be seen as a little silly as it essentially is just 

if numel(generalFields) ~= numel(generalValues)
   error('Number of general fields and values must be the same')
end

for ii = 1:numel(generalFields)
   isCharLogical = ischar(generalFields{ii});
   isStringLogical = isstring(generalFields{ii});
   if ~(isCharLogical || isStringLogical)
      error('All general field names must be strings or character arrays')
   end
end

if ~all(cellfun(@ischar,generalFields) + cellfun(@isstring,generalFields))
   error('All general field names must be strings or character arrays')
end




for ii = 1:numel(commandFields)
   config.commands.(commandFields{ii}) = commandValues{ii};
end

if nargin > 4
   if numel(generalFields) ~= numel(generalValues)
      error('Number of general fields and values must be the same')
   end
   
   if ~all(cellfun(@ischar,generalFields) + cellfun(@isstring,generalFields))
      error('All general field names must be strings or character arrays')
   end
   for ii = 1:numel(generalFields)
      config.(generalFields{ii}) = generalValues{ii};
   end
end

save(savePath,config)



end