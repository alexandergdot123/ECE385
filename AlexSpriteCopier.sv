void drawSpriteAlexCPUExample(uint32_t frameBufferBase, int x, int y,
                uint32_t spriteBase, int spriteWidth, int spriteHeight,
                uint8_t magicColor) {
    for(int i = 0; i<spriteWidth; i++){
        for(int j = 0; j<spriteWidth; j++){
            if(x + j >=640 || x + j <0 || y + i >=480 || y + i < 0){
                continue;
            }
            uint32_t value = *(spriteBase + i * spriteWidth + j);
            uint32_t color = value >> 24;
            if(value ==10){
                continue;
            }
            *(frameBufferBase + y * 640 + x + i * 640 + j) = value;
        }
    }

}
void drawSpriteAlex(uint32_t frameBufferBase, int x, int y, uint32_t spriteBase, int spriteWidth, int spriteHeight, uint8_t magicColor){
    //and reg 0-6
    //add top 16 bits of frameBufferBase to reg 0
    //bitshift left 16 bits
    //add lower 16 bits of frameBufferBase to reg0


    for(int a = 0; a<7; a++){
        makeAndOrInstruction(a, 0, 0, 1, 0, 0, 0); //cycle through each register from 0 to 7 and AND it with 0, sign-extended immediate value.
    }
    uint32_t topHalf = frameBufferBase >> 16;
    makeAddSubtractInstruction(0, 0, 1, 0, 0, topHalf);
    makeBitShiftInstruction(0,0,1, 4);
    uint32_t bottomHalf = frameBufferBase & 0x0000FFFF;
    makeAddSubtractInstruction(0, 0, 1, 0, 0, bottomHalf);
    for(int i = 0; i<spriteWidth; i++){
        for(int j = 0; j<spriteWidth; j+=32){
            uint32_t xvals = x + j;
            uint32_t yvals = y + i;
            //add xvals + reg 7 to reg 6
            makeAddSubtractInstruction(6, 6, 1, 0, 0, xvals>>16);
            makeBitShiftInstruction(6,6,1, 4);
            makeAddSubtractInstruction(6, 6, 1, 0, 0, xvals & 0x0000FFFF);
            makeAddSubtractInstruction(6, 6, 0, 0, 7, 0);
            //compare to 0, should be greater or equal
            makeCompareImmediateInstruction(1,1,0,?, 6, 0);
            //compare to 640, should be leser
            makeCompareImmediateInstruction(0,0,1,?, 6, 640);


            //add yvals to reg 5
            makeAddSubtractInstruction(5, 5, 1, 0, 0, yvals>>16);
            makeBitShiftInstruction(5,5,1, 4);
            makeAddSubtractInstruction(5, 5, 1, 0, 0, yvals & 0x0000FFFF);
            //compare to 0, should be greater or equal
            makeCompareImmediateInstruction(1,1,0,?, 5, 0);
            //compare to 480, should be lesser
            makeCompareImmediateInstruction(0,0,1,?, 5, 480);


            //reg4 = y value * spriteWidth
            makeMultiplyInstruction(4, 5, 1, 0, spriteWidth);
            //reg4 = reg 4 + reg 6
            makeAddSubtractInstruction(4,4,0,0,6,0);

            //now get the sprite address
            makeAndOrInstruction(3,3, 0,1, 0, 0,0);
            makeAddSubtractInstruction(3, 3, 1, 0, 0, spriteBase>>16);
            makeBitShiftInstruction(3,3,1, 4);
            makeAddSubtractInstruction(3, 3, 1, 0, 0, spriteBase & 0x0000FFFF);

            makeAddSubtractInstruction(3,4, 0, 0,3, 0); //now I have the Memory address of the sprite in reg 3

            makeLoadGlobalMemoryIRInstruction(3,3,0); //load the contents of the sprite data into reg 3

            //bitshift reg 3 by 24 right into reg2
            makeBitShiftInstruction(2,3,1, 5);

            //if reg2 == magicColor, its transparent. skip
            makeCompareImmediateInstruction(0,1,0,?, 2, 5);

            //now we will calculate mar
            //reg1 = reg5 * 640
            makeMultiplyInstruction(1, 5,1, 0, 640);


            //reg 1 = reg 1 + reg 6
            makeAddSubtractInstruction(1, 1,0,0,6,0);
            //reg 1 = reg 1 + reg 0
            makeAddSubtractInstruction(1,1,0,0,0,0);
            //now we have the mar
            //store reg3 into M[reg1]
            makeStoreGlobalMemoryIRInstruction(3,1,15,0);
            //now, on the cpu side, we will double check the buffer fill
            //if it is too full ( maybe above like 20 or something), we will do a thread sleep for some small amount of time.
            //This could be done manually with thread sleep or with an empty for loop or smtn
        }
    }
}

