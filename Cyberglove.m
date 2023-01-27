classdef Cyberglove < handle
    % Cyberglove Summary of this class goes here
    %   Detailed explanation goes here

    properties (SetAccess = private) % other classes can't modify these options
        serial_p = [];
        PosUpdate;
        StreamingStatus = 0;
        OldLastReading = [0 0 0 0 0];
        GlovePositions = zeros(10000,5);
        pack = 1;
        raw_acq = zeros(19,1);
    end

    properties(SetAccess = private, SetObservable) % listeners can access these properties
        LastReading = [0 0 0 0 0];
    end

    properties
        CalData = struct('gain', [0.5 0.5 0.5 0.5 0.5], 'offset', [-50 -50 -50 -50 -50]);
    end

    events
        NewDataAvail
    end

    methods
        %%% CONSTRUCTOR
        function obj = Cyberglove(varargin)
            switch nargin
                case 0
                    warning('No COM port provided. Trying with COM6')
                    COMport = 'COM6';
                case 1
                    COMport = varargin{1};
                otherwise
                    error('Too many input arguments')
            end
            % set COM port settings
            B_rate = 115200;
            N_bits = 8;
            S_bits = 1;
            parity = 'none';
            FlowControl = 'none';
            BufferSize = 500;

            % open COM port
%             obj.serial_p = serialport(COMport,'BaudRate', B_rate, 'DataBits', ...
%                N_bits, 'StopBits', S_bits, 'Parity', parity, 'Timeout', 0.1, ...
%                'InputBufferSize', BufferSize, 'FlowControl', FlowControl);
            obj.serial_p = serialport(COMport,B_rate);
%             fopen(obj.serial_p);

            % Create Timer to read position values
            tStart = tic;
            obj.PosUpdate = timer('TimerFcn', {@Cyberglove.ReadData, obj, tStart}, ...
                'ExecutionMode','fixedRate','Period', 1/30);
          
            if(exist('CGcalib.mat', 'file'))
                LoadCalibration(obj);
            end

            % Set streaming frame rate to 30 Hz
            obj.SetFrameRate(1);

        end % constructor

        function StartAcquisition(obj)
            % start streaming (write 'S' to the glove)
%             fwrite(obj.serial_p, 'S', 'uint8');
            write(obj.serial_p, 'S', 'uint8');

            % start the timer to record data
            if ~isempty(obj.PosUpdate) && strcmp(obj.PosUpdate.Running,'off')
                start(obj.PosUpdate);
            end
        end % StartAcquisition

        function StopAcquisition(obj)
            % stop updating position
            if ~isempty(obj.PosUpdate) && strcmp(obj.PosUpdate.Running,'on')
                stop(obj.PosUpdate);
                set(obj.PosUpdate,'UserData', []);
            end

            % stop streaming (write 0x03 aka ETX to the glove and flush serial)
%             fwrite(obj.serial_p, char(03), 'uint8');
            write(obj.serial_p, char(03), 'uint8');
%             flushinput(obj.serial_p);
            flush(obj.serial_p,"input")

            % preshape the hand
            obj.OldLastReading = obj.LastReading;
            obj.LastReading = [50 50 50 50 50];
            notify(obj, 'NewDataAvail')

        end % StopAcquisition

        function LoadCalibration(obj)
            CalibrationData = load('CGcalib.mat');
            obj.CalData = CalibrationData.CalibrationData;
        end % LoadCalibration

        function SaveCalibration(obj)
            CalibrationData = obj.CalData;
            save('CGcalib.mat', 'CalibrationData')
        end % SaveCalibration

        function SetFrameRate(obj, multiplier)
            if (multiplier > 0) && (multiplier < 4)
%                 fwrite(obj.serial_p, ['1m' multiplier], 'uint8');
                write(obj.serial_p, ['1m' multiplier], 'uint8');
%                 answer = fread(obj.serial_p,4,'uint8');
                answer = read(obj.serial_p,4,'uint8');
                if numel(answer) ~= 4 || answer(4)~= 0
                    warning('The CyberGlove is not responding properly. Try again...');
                else
                    switch multiplier
                        case 1
                            disp('Streaming Frame Rate set to 30Hz');
                        case 2
                            disp('Streaming Frame Rate set to 60Hz');
                        case 3
                            disp('Streaming Frame Rate set to 90Hz');
                    end
                end
            else 
                warning('Invalid multiplier provided (Must be between 1 and 3). No Frame Rate was set');
            end
        end % SetFrameRate

        %% DESTRUCTOR
        function delete(obj)
            % Close COM port
            fclose(obj.serial_p);
            delete(obj.serial_p);
            clear obj
        end % DESTRUCTOR

    end % methods

    methods (Access = private, Static)

        function ReadData(src, ~, obj, tStart) % from the glove
%             if (obj.serial_p.BytesAvailable > 100 && obj.StreamingStatus == 0)
            if (obj.serial_p.NumBytesAvailable > 100 && obj.StreamingStatus == 0)
%                 flushinput(obj.serial_p);
                flush(obj.serial_p,"input");
                %disp('full');
            end

            switch(obj.StreamingStatus) % manage the streaming with a state machine
                case 0
%                     firstbyte = fread(obj.serial_p, 1, 'uint8');
                    firstbyte = read(obj.serial_p, 1, 'uint8');
                    % if first byte is 0x53 (83), then go to the next step
                    if (firstbyte == 83)
                        obj.StreamingStatus = 1;
                    else
                        obj.StreamingStatus = 0;
                    end

                case 1
                    % wait until you have at least 19 bytes (i.e. one
                    % package) and read it
%                     if (obj.serial_p.BytesAvailable > 18)
                    if (obj.serial_p.NumBytesAvailable > 18)
                        obj.StreamingStatus = 0;
%                         pos = fread(obj.serial_p, 19, 'uint8');
                        pos = read(obj.serial_p, 19, 'uint8');
                        obj.raw_acq = pos;
                        % if the last byte is 0x00, package is OK, thus use it
                        if (pos(19) == 0)
                            obj.LastReading(1) = (pos(1)+obj.CalData.offset(1))*obj.CalData.gain(1);          % Rotation
                            obj.LastReading(2) = (pos(2) + pos(3)+obj.CalData.offset(2))*obj.CalData.gain(2); % Thumb MCP+IP
                            obj.LastReading(3) = (pos(5) + pos(6)+obj.CalData.offset(3))*obj.CalData.gain(3); % Index MCP+IP
                            obj.LastReading(4) = (pos(7) + pos(8)+obj.CalData.offset(4))*obj.CalData.gain(4); % Middle MCP+IP
                            obj.LastReading(5) = (pos(10) + pos(11) + pos(13) + pos(14)+obj.CalData.offset(5))*obj.CalData.gain(5); % Index MCP+IP
                            obj.LastReading = round(obj.LastReading);
                            obj.LastReading(obj.LastReading > 255) = 254;
                            obj.LastReading(obj.LastReading < 1) = 0;
                            obj.OldLastReading = obj.LastReading;
                            notify(obj, 'NewDataAvail')
%                             disp(['posizioni: ', num2str(pos(1:18)')])
                            dlmwrite('Closure05.csv',pos','-append');
                            obj.GlovePositions(obj.pack,:) = obj.LastReading;
                            obj.pack = obj.pack + 1;
                            if obj.pack == 10001
                                obj.pack = 0;
                            end
                            % plot(obj.GlovePositions)
                        end
                    end
            end

%             if(obj.StreamingStatus == 0) % manage the streaming with a state machine
%                 firstbyte = fread(obj.serial_p, 1, 'uint8');
%                 % if first byte is 0x53 (83), then go to the next step
%                 if (firstbyte == 83)
%                     obj.StreamingStatus = 1;
%                 else
%                     obj.StreamingStatus = 0;
%                 end
%             end
%
%             if(obj.StreamingStatus == 1)
%                 % wait until you have at least 19 bytes (i.e. one
%                 % package) and read it
%                 %if (obj.serial_p.BytesAvailable > 18)
%                 obj.StreamingStatus = 0;
%                 pos = fread(obj.serial_p, 19, 'uint8');
%                 % if the last byte is 0x00, package is OK, thus use it
%                 if (pos(19) == 0)
%                     obj.LastReading(1) = (pos(1)+obj.CalData.offset(1))*obj.CalData.gain(1);          % Rotation
%                     obj.LastReading(2) = (pos(2) + pos(3)+obj.CalData.offset(2))*obj.CalData.gain(2); % Thumb MCP+IP
%                     obj.LastReading(3) = (pos(5) + pos(6)+obj.CalData.offset(3))*obj.CalData.gain(3); % Index MCP+IP
%                     obj.LastReading(4) = (pos(7) + pos(8)+obj.CalData.offset(4))*obj.CalData.gain(4); % Middle MCP+IP
%                     obj.LastReading(5) = (pos(10) + pos(11) + pos(13) + pos(14)+obj.CalData.offset(5))*obj.CalData.gain(5); % Index MCP+IP
%                     obj.LastReading = round(obj.LastReading);
%                     obj.LastReading(obj.LastReading > 255) = 254;
%                     obj.LastReading(obj.LastReading < 1) = 0;
%                     obj.OldLastReading = obj.LastReading;
%                     notify(obj, 'NewDataAvail')
% %                     disp(['posizioni: ', num2str(obj.LastReading)])
% %                     obj.GlovePositions(obj.pack,:) = obj.LastReading;
% %                     obj.pack = obj.pack + 1;
% %                     if obj.pack == 10001
% %                         obj.pack = 0;
% %                     end
% %                     plot(obj.GlovePositions)
%                 end
%              end

        end % ReadData

    end % methods (private, static)

end % class
