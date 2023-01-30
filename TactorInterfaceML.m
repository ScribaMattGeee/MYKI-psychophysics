classdef TactorInterfaceML < handle
    %TACTORCONTROLLER A MATLAB interface to the EAI Tactor Controller
	%   This does not expose all functionaity of the TDK.
    
    properties (Access=private)
        libName = 'TactorInterface';
        libLoaded = false;
        dllName = 'SET_IN_CONSTRUCTOR';
        dllHeader = 'SET_IN_CONSTRUCTOR';
        
        deviceIndex = -1;
    end
    properties (Access=public)
        %deviceName = 'COM9';
    end
    properties (GetAccess=public, SetAccess=private)
        initialized = false;
        devicesDiscovered = 0;
        deviceConnected = false;
    end

    methods
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % OBJECT CREATION
        function obj=TactorInterfaceML()
            % constructor
            obj.dllName = strcat(obj.libName, '.dll');
            obj.dllHeader = strcat(obj.libName, '.h');
            obj.initialize;
        end
        function initialize(obj)
            if (obj.initialized == true)
                disp('Tactor Interface already initialized!')
            end
            
            disp('Loading dll...')
            loadlibrary(obj.dllName, obj.dllHeader);
            obj.libLoaded = true;
            disp('Dll loaded!')
            calllib(obj.libName, 'InitializeTI');
			disp('Initialized Tactor Interface.');
            obj.initialized = true;
        end
        function shutdown(obj)
            if (obj.initialized == false)
                return;
            end
            
            if (obj.deviceConnected == true)
                obj.Close;
            end
            
            if (obj.libLoaded == true)
                disp('Killing dll...')
                ret = calllib(obj.libName, 'ShutdownTI');
                disp(strcat('Dll killed: ', num2str(ret)))
                disp('Unloading dll...')
                unloadlibrary(obj.libName);
                obj.libLoaded = false;
                disp('Dll unloaded!')
            end
            
            % perform cleanup
            obj.initialized = false;
        end
        function delete(obj)
            % destructor
            if (obj.initialized == true)
                obj.shutdown;
            end
        end
        % END OBJECT CREATION
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % TACTOR DLL INTERFACE
        function out=ConnectDirect(obj, name)
            %decl: int fn(char* name, int type)
            %type should be com port type -- it's all that's supported
            %right now!
            
            if (obj.initialized == false)
                disp('Can not ConnectDirect, not initialized!')
                out = -1;
                return;
            end
            
             out = calllib(obj.libName, 'Connect', name, 1,[]);
%             index = out;
            if (out == -1)
                disp('ConnectDirect failed!')
                return;
            end
            
            disp('Connected succesfully!')
             obj.deviceConnected = true;
             obj.deviceIndex = out;
        end
        
        function out=Connect(obj,name, type)
            %decl int fn(int index, int type)
            if (obj.initialized == false)
                disp('Not Initialized! Can not get discovered device!')
                out = -1;
                return;
            end
            if (obj.devicesDiscovered == 0)
                disp('No devices discovered! Call Discover first!')
                out = -1;
                return;
            end
            
            out = calllib(obj.libName, 'Connect', name, type,[]);
            disp(strcat('Connect returned: ', num2str(out)))
            if (out >= 0)
                obj.deviceConnected = true;
                obj.deviceIndex = out;
            end
        end
        
        function out=Discover(obj)
            %decl: int fn(int byte)
            %define SERIALPORTBYTE 0x01
            %define USBADVBYTE 0x02
            if (obj.initialized == false)
                disp('Not Initialized! Can not discover!')
                out = -1;
                return;
            end
            
            disp('Discovering... (this will take a while.)')
            
            % SERALPORTBYTE | USBADVBYTE               
            % is          1 | 2
            % is            3
            
            out = calllib(obj.libName, 'Discover', 3);
            
            if (out < 0)
                disp(strcat('Error! Discover returned: ', num2str(out)))
                obj.devicesDiscovered = 0;
                return;
            end
            
            disp(strcat('Discover returned: ', num2str(out)))
            obj.devicesDiscovered = out;
        end
        
        function [dev, type]=GetDevice(obj, index)
            %decl: char* fn(int index, int* size, int* Type);
            if (obj.initialized == false)
                disp('Not Initialized! Can not get discovered device!')
                dev = 0;
                type = 0;
                return;
            end
            if (obj.devicesDiscovered == 0)
                disp('No devices discovered! Call DiscoverDevices first!')
                dev = 0;
                type = 0;
                return;
            end
            
            defVal = 0;
            pSize = libpointer('int32Ptr',defVal);
            pType = libpointer('int32Ptr',defVal);
            
            devRet = calllib(obj.libName, 'GetDiscoveredDeviceName', index);
            dev = devRet;
            type = 1;
            disp(strcat('GetDevice: ', devRet))
        end
        
        function out=Close(obj)
            if (obj.deviceConnected == false)
                disp('Can not disconnect, device not connected.')
                out = -1;
                return;
            end
            
            out = calllib(obj.libName, 'Close', obj.deviceIndex);
            obj.deviceConnected = false;
            obj.deviceIndex = -1;
            if (out ~= 0)
                disp(strcat('Error with Disconnect: ', num2str(out)));
                return;
            end
            disp('Disconnect complete!');
        end
        
        function out=Pulse(obj, devIndex, tacNum, durMilli, delay)
            if (obj.deviceConnected == false)
                disp('Can not Pulse, not connected!')
                out = -1;
                return;
            end
			
             out = calllib(obj.libName, 'Pulse', devIndex, tacNum, durMilli,delay);
            
        end
        
        function out=ChangeGain(obj, devIndex,tacNum, gain, delay)
          	if (obj.deviceConnected == false)
                disp('Can not SetGain, not connected!')
                out = -1;
                return;
            end
			
             out = calllib(obj.libName, 'ChangeGain', devIndex,tacNum, gain, delay);
        end
        
        function out=ChangeFreq(obj, devIndex, tacNum, freq, delay)
            if (obj.deviceConnected == false)
                disp('Can not SetFreq, not connected!')
                out = -1;
                return;
            end
            
            out = calllib(obj.libName, 'ChangeFreq', devIndex, tacNum, freq, delay);
        end
		
        
		function out=RampFreq(obj, devIndex, tacNum, freqStart, freqEnd, duration, func, delay)
            if (obj.deviceConnected == false)
                disp('Can not RampFreq, not connected!')
                out = -1;
                return;
            end
            
            out = calllib(obj.libName, 'RampFreq', devIndex, tacNum, freqStart, freqEnd, duration, func, delay);
        end
		
		function out=RampGain(obj, devIndex, tacNum, gainStart, gainEnd, duration, func, delay)
            if (obj.deviceConnected == false)
                disp('Can not RampGain, not connected!')
                out = -1;
                return;
            end
            
            out = calllib(obj.libName, 'RampGain', devIndex, tacNum, gainStart, gainEnd, duration, func, delay);
        end
		
		function out=SetFreqTimeDelay(obj, devIndex, delayOn)
            if (obj.deviceConnected == false)
                disp('Can not SetFreqTimeDelay, not connected!')
                out = -1;
                return;
            end
            
            out = calllib(obj.libName, 'SetFreqTimeDelay', devIndex, delayOn);
        end
		
        % END TACTOR DLL INTERFACE
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    end
end
