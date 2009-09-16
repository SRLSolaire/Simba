unit Window;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, mufasatypes,
  {$IFDEF MSWINDOWS}
  windows,  // For windows API
  {$ENDIF}
  graphics,
  LCLType,
  LCLIntf // for ReleaseDC and such

  {$IFDEF LINUX}, xlib, x, xutil, ctypes{$ENDIF};

type

    { TMWindow }

    TMWindow = class(TObject)
            function ReturnData(xs, ys, width, height: Integer): TRetData;
            procedure FreeReturnData;
            procedure GetDimensions(var W, H: Integer);
            function CopyClientToBitmap(xs, ys, xe, ye: integer): TBitmap;
            procedure ActivateClient;
            {$IFDEF LINUX}
            function SetTarget(XWindow: x.TWindow): integer; overload;
            {$ENDIF}

            {$IFDEF MSWINDOWS}
            function UpdateDrawBitmap:boolean;
            {$ENDIF}
            function SetTarget(Window: THandle; NewType: TTargetWindowMode): integer; overload;
            function SetTarget(ArrPtr: PRGB32; Size: TPoint): integer; overload;

            {
              Freeze Client Feature.
              This will force the MWindow unit to Store the current Client's
              data in whatever internal structure it will use, and returndata /
              copyclienttobitmap will not renew this data until Unfreeze() is
              called.
            }

            function Freeze: boolean;
            function Unfreeze: boolean;

            constructor Create(Client: TObject);
            destructor Destroy; override;

        private
              FreezeState: Boolean;
        public
              // Client
              Client: TObject;

              // Target Window Mode.
              TargetMode: TTargetWindowMode;


              {$IFDEF MSWINDOWS}
              //Target handle; HWND
              TargetHandle : Hwnd;
              DrawBmpDataPtr : PRGB32;

              //Works on linux as well, test it out
              TargetDC : HDC;
              DrawBitmap : TBitmap;
              DrawBmpW,DrawBmpH : integer;
              {$ENDIF}

              {$IFDEF LINUX}
              // X Display
              XDisplay: PDisplay;

              // Connection Number
              XConnectionNumber: Integer;

              // X Window
              CurWindow: x.TWindow;

              // Desktop Window
              DesktopWindow: x.TWindow;

              // X Screen
              XScreen: PScreen;

              // X Screen Number
              XScreenNum: Integer;

              // The X Image pointer.
              XWindowImage: PXImage;

                 {$IFDEF M_MEMORY_DEBUG}
                  // XImageFreed should be True if there is currently no
                  // XImage loaded. If one is loaded, XImageFreed is true.

                  // If ReturnData is called while XImageFreed is false,
                  // we throw an exception.
                  // Same for FreeReturnData with XImageFreed true.
                  XImageFreed: Boolean;
                  {$ENDIF}

              {$ELSE}

              {$ENDIF}

              ArrayPtr: PRGB32;
              ArraySize: TPoint;

              property Frozen: boolean read FreezeState;



    end;

implementation

uses
    Client, // For the Client Class
    windowutil, // For utilities such as XImageToRawImage
    GraphType // For TRawImage
    ;

constructor TMWindow.Create(Client: TObject);
begin
  inherited Create;

  Self.Client := Client;


  Self.FreezeState :=False;

  Self.ArrayPtr := nil;
  Self.ArraySize := Classes.Point(-1, -1);

  {$IFDEF MSWINDOWS}
  Self.DrawBitmap := TBitmap.Create;
  Self.DrawBitmap.PixelFormat:= pf32bit;
  Self.TargetMode:= w_Window;
  Self.TargetHandle:= windows.GetDesktopWindow;
  Self.TargetDC:= GetWindowDC(Self.TargetHandle);
  Self.UpdateDrawBitmap;
  {$ENDIF}

  {$IFDEF LINUX}
  Self.XImageFreed:=True;
  Self.TargetMode := w_XWindow;

  Self.XDisplay := XOpenDisplay(nil);
  if Self.XDisplay = nil then
  begin
    // throw Exception
  end;
  Self.XConnectionNumber:= ConnectionNumber(Self.XDisplay);
  Self.XScreen := XDefaultScreenOfDisplay(Self.XDisplay);
  Self.XScreenNum:= DefaultScreen(Self.XDisplay);

  // The Root Window is the Desktop. :-)
  Self.DesktopWindow:= RootWindow(Self.XDisplay, Self.XScreenNum);
  Self.CurWindow:= Self.DesktopWindow;

  {$ENDIF}

end;

destructor TMWindow.Destroy;
begin

  {$IFDEF LINUX}
  XCloseDisplay(Self.XDisplay);
  {$ENDIF}
  {$IFDEF MSWINDOWS}
  if TargetMode = w_Window then
    ReleaseDC(TargetHandle,TargetDC);
  DrawBitmap.Free;
  {$ENDIF}
  inherited;
end;

function TMWindow.ReturnData(xs, ys, width, height: Integer): TRetData;
var
{$IFDEF LINUX}
   Old_Handler: TXErrorHandler;
{$ENDIF}
   TmpData: PRGB32;

begin
  case Self.TargetMode of
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      BitBlt(Self.DrawBitmap.Canvas.Handle,0,0, width, height, Self.TargetDC, xs,ys, SRCCOPY);
      Result.Ptr:= Self.DrawBmpDataPtr;
      Result.IncPtrWith:= DrawBmpW - Width;
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      { Should be this. }
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);

      Self.XWindowImage := XGetImage(Self.XDisplay, Self.curWindow, xs, ys, width, height, AllPlanes, ZPixmap);
      if QWord(Self.XWindowImage) = 0 then
      begin
        Writeln('ReturnData: XGetImage Error. Dumping data now:');
        Writeln('xs, ys, width, height: ' + inttostr(xs) + ', '  + inttostr(ys) +
                ', ' + inttostr(width) + ', ' + inttostr(height));
        Result.Ptr := nil;
        Result.IncPtrWith := 0;

        XSetErrorHandler(Old_Handler);
        Exit;
      end;
      //WriteLn(IntToStr(Self.XWindowImage^.width) + ', ' + IntToStr(Self.XWindowImage^.height));
      Result.Ptr := PRGB32(Self.XWindowImage^.data);
      Result.IncPtrWith := 0;
      Self.XImageFreed:=False;

      XSetErrorHandler(Old_Handler);
      {$ELSE}
      raise Exception.createFMT('ReturnData: You cannot use ' +
                                'the XImage mode on Windows.', []);
      {$ENDIF}
    end;
    w_ArrayPtr:
    begin
      // Copy the pointer as we will perform operations on it.
      TmpData := Self.ArrayPtr;

      // Increase the pointer to the specified start of the data.

      Inc(TmpData, ys * Height + xs);
      Result.Ptr := TmpData;
      Result.IncPtrWith:= Self.ArraySize.x - width;

    end;
  end;
end;

procedure TMWindow.FreeReturnData;
begin
  if Self.TargetMode <> w_XWindow then
  begin
    raise Exception.createFMT('FreeReturnData - Image data must only ' +
                               ' be freed with XGetImage', []);
    exit;
  end;
  if FreezeState then
  begin
    raise Exception.createFMT('FreeReturnData called when Freeze = True', []);
    exit;
  end;
  {$IFDEF LINUX}
  if not Self.XImageFreed then
  begin
    Self.XImageFreed:=True;
    if(QWord(Self.XWindowImage) <> 0) then      // 0, nil?
    begin
      XDestroyImage(Self.XWindowImage);
    end;
  end;
  {$ENDIF}
end;

// This will draw the ENTIRE client to a bitmap.
// And ReturnData / CopyClientToBitmap will always use this bitmap.
// They must NEVER update, unless Unfreeze is called.

// I am not entirely sure how to do this, yet.
// Best option for now seems to copy the entire data to a PRGB32,
// and use it like the ArrPtr mode.

// I currently added "Frozen", "FreezeState", "Freeze" and "Unfreeze".
// We will have to either "abuse" the current system, and set the client to
// PtrArray mode, or edit in some extra variables.
// (We will still need extra variables to remember the old mode,
// to which we will switch back with Unfreeze.)

// Several ways to do it, what's the best way?

// Also, should a box be passed to Freeze, or should we just copy the entire
// client?

function TMWindow.Freeze: Boolean;
begin
  Self.FreezeState:=True;
  raise Exception.createFMT('Freeze: Not yet implemented.', []);
end;

function TMWindow.Unfreeze: Boolean;
begin
  Self.FreezeState:=False;
  raise Exception.createFMT('Unfreeze: Not yet implemented.', []);
end;

// Bugged. For params other than 0, 0, ClientWidth, ClientHeight
// if other type than w_XImage

// Also possibly thread bugged
function TMWindow.CopyClientToBitmap(xs, ys, xe, ye: integer): TBitmap;
var
   w,h: Integer;
   ww, hh: Integer;
   Raw: TRawImage;
   Bmp: TBitmap;
   {$IFDEF LINUX}
   Old_Handler: TXErrorHandler;
   Img: PXImage;
   {$ENDIF}


begin
  Self.GetDimensions(w, h);
  writeln(inttostr(xs) + ', ' + inttostr(ys) + ' : ' + inttostr(xe) + ', ' +
          inttostr(ye));
  ww := xe-xs;
  hh := ye-ys;
  if(xs < 0) or (ys < 0) or (xe > W) or (ye > H) then
  begin
    writeln('Faulty coordinates');
    exit;
  end;


    case Self.TargetMode Of
       w_Window:
       begin
         {$IFDEF MSWINDOWS}
         Result := TBitmap.Create;
         Result.SetSize(ww+1,hh+1);
         BitBlt(result.canvas.handle,0,0,ww+1,hh+1,
                self.TargetDC,xs,ys, SRCCOPY);
         {$ENDIF}
       end;
       w_XWindow:
       begin
         {$IFDEF LINUX}
         Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);

         Img := XGetImage(Self.XDisplay, Self.curWindow, xs, ys, ww, hh, AllPlanes, ZPixmap);
         XImageToRawImage(Img, Raw);

         Bmp := TBitmap.Create;
         Bmp.LoadFromRawImage(Raw, False);
         Result := Bmp;

         {
           If you want to use some internal Bitmap system, BitBlt to it here.
           Don't forget to free Bmp!
         }
         //lclintf.BitBlt(Bmps[bitmap].Canvas.Handle, 0, 0, ww + 1, hh + 1, Bmp.Canvas.Handle, xs, ys, SRCCOPY);
         //Bmp.Free;

         XDestroyImage(Img);
         XSetErrorHandler(Old_Handler);
         {$ELSE}
         raise Exception.createFMT('CopyClientToBitmap: You cannot use ' +
                                    'the XImage mode on Windows.', []);
         {$ENDIF}
       end;
       w_ArrayPtr:
       begin
         // Will only work if the coords are 0, 0, w, h.
         // Otherwise, we will need to perform mem copy/move operations.
         // Copy it to a XImage-alike structure,
         // then pass it to ArrDataToRawImage.

         // Basically, Copy the data slices from the array into a XImage,
         // where the data IS aligned.

         raise Exception.createFMT('Array Data to Bitmap not yet fully ' +
                                   'implemented', []);
         Result := nil;
         exit;


         ArrDataToRawImage(Self.ArrayPtr, Self.ArraySize, Raw);

         Bmp := TBitmap.Create;
         Bmp.LoadFromRawImage(Raw, False);
         Result := Bmp;
       end;
    end;
end;

procedure TMWindow.ActivateClient;
begin
  {$IFDEF MSWINDOWS}
  if TargetMode = w_Window then
    SetForegroundWindow(Self.TargetHandle);
  {$ENDIF}
  {$IFDEF LINUX}
  if TargetMode = w_XWindow then
    XSetInputFocus(Self.XDisplay,Self.CurWindow,RevertToParent,CurrentTime);
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}  //Probably need one for Linux as well
function TMWindow.UpdateDrawBitmap :boolean;
var
  w,h : integer;
  BmpInfo : Windows.TBitmap;
begin
  GetDimensions(w,h);
  DrawBitmap.SetSize(w,h);
//  DrawBitmap.PixelFormat:=
  DrawBmpW := w;
  DrawBmpH := h;
  GetObject(DrawBitmap.Handle, SizeOf(BmpInfo), @BmpInfo);
  DrawBmpDataPtr := BmpInfo.bmBits;
end;
{$ENDIF}

procedure TMWindow.GetDimensions(var W, H: Integer);
{$IFDEF LINUX}
var
   Attrib: TXWindowAttributes;
   newx,newy : integer;
   childwindow : x.TWindow;
   Old_Handler: TXErrorHandler;
{$ENDIF}
{$IFDEF MSWINDOWS}
var
  Rect : TRect;
{$ENDIF}
begin
  case TargetMode of
    w_Window:
    begin
      {$IFDEF MSWINDOWS}
      GetWindowRect(Self.TargetHandle, Rect);
      w:= Rect.Right - Rect.Left;
      h:= Rect.Bottom - Rect.Top;
      {$ENDIF}
    end;
    w_XWindow:
    begin
      {$IFDEF LINUX}
      Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);
      if XGetWindowAttributes(Self.XDisplay, Self.CurWindow, @Attrib) <> 0 Then
      begin
        XTranslateCoordinates(Self.XDisplay, Self.CurWindow, Self.DesktopWindow, 0,0, @newx, @newy, @childwindow);
        W := Attrib.Width;
        H := Attrib.Height;
      end else
      begin
        W := -1;
        H := -1;
      end;
      XSetErrorHandler(Old_Handler);
      {$ELSE}
       raise Exception.createFMT('GetDimensions: You cannot use ' +
                                 'the XImage mode on Windows.', []);
      {$ENDIF}
    end;
    w_ArrayPtr:
    begin
      W := Self.ArraySize.X;
      H := Self.ArraySize.Y;
    end;
  end;
end;

{$IFDEF LINUX}
function TMWindow.SetTarget(XWindow: x.TWindow): integer; overload;
var
   Old_Handler: TXErrorHandler;
begin
  Old_Handler := XSetErrorHandler(@MufasaXErrorHandler);
  Self.CurWindow := XWindow;
  Self.TargetMode:= w_XWindow;
  XSetErrorHandler(Old_Handler);
end;
{$ENDIF}

function TMWindow.SetTarget(Window: THandle; NewType: TTargetWindowMode): integer; overload;
begin
  if NewType in [ w_XWindow, w_ArrayPtr ] then
  begin
    raise Exception.createFMT('SetTarget: Invalid new type.', []);
    Exit;
  end;
  case NewType of
    w_Window :
    begin;

      {$IFDEF MSWINDOWS}
      ReleaseDC(Self.TargetHandle,Self.TargetDC);
      Self.TargetHandle := Window;
      Self.TargetDC := GetWindowDC(Window);
      {$ENDIF}
    end;
  end;
  {$IFDEF MSWINDOWS}
  UpdateDrawBitmap;
  {$ENDIF}
end;

{
    This functionality is very BETA.
    We have no way to send events to a window, so we should probably use the
    desktop window?

    eg: In mouse/keys: if Self.TargetMode not in [w_Window, w_XWindow], send it
        to the desktop.
}
function TMWindow.SetTarget(ArrPtr: PRGB32; Size: TPoint): integer; overload;
begin
  If Self.TargetMode = w_XWindow then
    Self.FreeReturnData;

  Self.ArrayPtr := ArrPtr;
  Self.ArraySize := Size;
  Self.TargetMode:= w_ArrayPtr;

  {$IFDEF LINUX}
  Self.CurWindow := Self.DesktopWindow;
  {$ENDIF}

  {$IFDEF WINDOWS}
  Self.TargetHandle:= windows.GetDesktopWindow;
  {$ENDIF}

end;

end.

