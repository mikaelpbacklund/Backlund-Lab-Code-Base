function varargout = mustContainField(S,F,varargin)
%Simple validation function to check for field names
%S is structure input
%F is fieldnames. Can be individual char, cell of chars/strings or string array 
%D is defaults. Corresponds to each field in F to set that field if empty
arguments
   S struct
   F {mustBeA(F,["char","string","cell"])}
end
arguments (Repeating)
   varargin cell
end

F = string(F);

%Check which fields are missing
missingFields = arrayfun(@(cls)~isfield(S,cls),F);

if any(missingFields)
   %If no defaults, give error if any fields aren't present
   if nargin == 2
      error('Structure must contain %s field(s)',strjoin(F(missingFields)))
   end
   
   %If defaults are given, add missing fields with default values
   missingFields = find(missingFields);
   D = varargin{1};
   for ii = missingFields
      S.(F(ii)) = D{ii};
   end
end

%If defaults have been given, output modified structure input
if nargin == 3
   varargout{1} = S;
end
end