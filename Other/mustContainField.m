function varargout = mustContainField(S,F,varargin)
%Simple validation function to check for field names
%S is structure input
%F is fieldnames. Can be individual char, cell of chars/strings or string array 
%D is defaults. Corresponds to each field in F to set that field if empty
arguments
   S struct
   F {mustBeA(F,["char","string","cell","struct"])}
end
arguments (Repeating)
   varargin cell
end

%If given a struct as second input, use that for fieldnames to check and default values
if isa(F,'struct')
   D = struct2cell(F);
   F = fieldnames(F);
elseif nargin > 2
   D = varargin{1};
else
   D = [];
end

F = string(F);

%Check which fields are missing
missingFields = arrayfun(@(cls)~isfield(S,cls),F);

if any(missingFields)
   %If no defaults, give error if any fields aren't present
   if isempty(D)
      error('Structure must contain %s field(s)',strjoin(F(missingFields)))
   end

   %Add missing fields with default values
   missingFields = find(missingFields);
   for ii = 1:numel(missingFields)
      if isempty(S) %Empty structures must be given index
         S(1).(F(missingFields(1))) = D{missingFields(1)};
      else
         S.(F(missingFields(ii))) = D{missingFields(ii)};
      end      
   end
end

%If defaults have been given, output modified structure input
if ~isempty(D)
   varargout{1} = S;
end
end