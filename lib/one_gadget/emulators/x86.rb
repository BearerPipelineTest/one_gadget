# frozen_string_literal: true

require 'one_gadget/emulators/instruction'
require 'one_gadget/emulators/lambda'
require 'one_gadget/emulators/processor'
require 'one_gadget/error'

module OneGadget
  module Emulators
    # Super class for amd64 and i386 processor.
    class X86 < Processor
      # Constructor for a x86 processor.
      def initialize(registers, sp, pc)
        super(registers, sp)
        @pc = pc
      end

      # Process one command.
      # Will raise exceptions when encounter unhandled instruction.
      # @param [String] cmd
      #   One line from result of objdump.
      # @return [Boolean]
      #   If successfully processed.
      def process!(cmd)
        inst, args = parse(cmd)
        # return registers[pc] = args[0] if inst.inst == 'call'
        return true if inst.inst == 'jmp' # believe the fetcher has handled jmp.

        sym = "inst_#{inst.inst}".to_sym
        __send__(sym, *args) != :fail
      end

      # Supported instruction set.
      # @return [Array<Instruction>] The supported instructions.
      def instructions
        [
          Instruction.new('add', 2),
          Instruction.new('call', 1),
          Instruction.new('jmp', 1),
          Instruction.new('lea', 2),
          Instruction.new('mov', 2),
          Instruction.new('nop', -1),
          Instruction.new('push', 1),
          Instruction.new('sub', 2),
          Instruction.new('xor', 2),
          Instruction.new('movq', 2),
          Instruction.new('movaps', 2),
          Instruction.new('movhps', 2),
          Instruction.new('punpcklqdq', 2)
        ]
      end

      private

      def inst_mov(dst, src)
        src = arg_to_lambda(src)
        if register?(dst)
          registers[dst] = src
        else
          # Just ignore strange case...
          # TODO(david942j): #120
          return add_writable(dst) unless dst.include?(sp)

          dst = arg_to_lambda(dst)
          return if dst.deref_count != 1 # should not happen

          dst.ref!
          stack[dst.evaluate(eval_dict)] = src
        end
      end

      # This instruction moves 128bits.
      def inst_movaps(dst, src)
        # XXX: here we only support `movaps [sp+*], xmm*`
        src, dst = check_xmm_sp(src, dst) { raise_unsupported('movaps', dst, src) }
        off = dst.evaluate(eval_dict)
        @constraints << [:raw, "#{sp} & 0xf == #{0x10 - off & 0xf}"]
        (128 / self.class.bits).times do |i|
          stack[off + i * size_t] = src[i]
        end
      end

      # Move src to dst[:64]
      # Supported forms:
      #   movq xmm*, [sp+*]
      #   movq xmm*, reg64
      def inst_movq(dst, src)
        if self.class.bits == 64 && xmm_reg?(dst) && src.start_with?('r') && register?(src)
          dst = arg_to_lambda(dst)
          src = arg_to_lambda(src)
          dst[0] = src
          return
        end
        dst, src = check_xmm_sp(dst, src) { raise_unsupported('movq', dst, src) }
        off = src.evaluate(eval_dict)
        (64 / self.class.bits).times do |i|
          dst[i] = stack[off + i * size_t]
        end
      end

      # Move src to dst[64:128]
      def inst_movhps(dst, src)
        # XXX: here we only support `movhps xmm*, [sp+*]`
        dst, src = check_xmm_sp(dst, src) { raise_unsupported('movhps', dst, src) }
        off = src.evaluate(eval_dict)
        (64 / self.class.bits).times do |i|
          dst[i + 64 / self.class.bits] = stack[off + i * size_t]
        end
      end

      # check whether (dst, src) is in form (xmm*, [sp+*])
      def check_xmm_sp(dst, src)
        return yield unless xmm_reg?(dst) && src.include?(sp)

        dst_lm = arg_to_lambda(dst)
        src_lm = arg_to_lambda(src)
        return yield if src_lm.deref_count != 1

        src_lm.ref!
        [dst_lm, src_lm]
      end

      def xmm_reg?(reg)
        reg.start_with?('xmm') && register?(reg)
      end

      # dst[64:128] = src[0:64]
      def inst_punpcklqdq(dst, src)
        raise_unsupported('punpcklqdq', dst, src) unless xmm_reg?(dst) && xmm_reg?(src)

        dst = arg_to_lambda(dst)
        src = arg_to_lambda(src)
        (64 / self.class.bits).times do |i|
          dst[i + 64 / self.class.bits] = src[i]
        end
      end

      def inst_lea(dst, src)
        check_register!(dst)

        registers[dst] = arg_to_lambda(src).ref!
      end

      def inst_push(val)
        val = arg_to_lambda(val)
        registers[sp] -= size_t
        cur_top = registers[sp].evaluate(eval_dict)
        raise Error::InstructionArgumentError, "Corrupted stack pointer: #{cur_top}" unless cur_top.is_a?(Integer)

        stack[cur_top] = val
      end

      def inst_xor(dst, src)
        check_register!(dst)

        # only supports dst == src
        raise Error::UnsupportedInstructionArgumentError, 'xor operator only supports dst = src' unless dst == src

        dst[0] = 'r' if self.class.bits == 64 && dst.start_with?('e')
        registers[dst] = 0
      end

      def inst_add(dst, src)
        check_register!(dst)

        src = arg_to_lambda(src)
        registers[dst] += src
      end

      def inst_sub(dst, src)
        src = arg_to_lambda(src)
        raise Error::UnsupportedInstructionArgumentError, "Unhandled -= of type #{src.class}" unless src.is_a?(Integer)

        registers[dst] -= src
      end

      # yap, nop
      def inst_nop(*); end

      # Handle some valid calls.
      # For example, +sigprocmask+ will always be a valid call
      # because it just invokes syscall.
      def inst_call(addr)
        # This is the last call
        return registers[pc] = addr if %w[execve execl posix_spawn].any? { |n| addr.include?(n) }

        # TODO: handle some registers would be fucked after call
        checker = {
          'sigprocmask' => {},
          '__close' => {},
          'unsetenv' => { 0 => :global_var? },
          '__sigaction' => { 1 => :global_var?, 2 => :zero? }
        }
        func = checker.keys.find { |n| addr.include?(n) }
        return if func && checker[func].all? { |idx, sym| check_argument(idx, sym) }

        # unhandled case or checker's condition fails
        :fail
      end

      def add_writable(dst)
        lmda = arg_to_lambda(dst).ref!
        # pc-relative addresses should be writable
        return if lmda.obj == pc

        @constraints << [:writable, lmda]
      end

      def to_lambda(reg)
        return super unless reg =~ /^xmm\d+$/

        Array.new(128 / self.class.bits) do |i|
          cast = "(u#{self.class.bits})"
          OneGadget::Emulators::Lambda.new(i.zero? ? "#{cast}#{reg}" : "#{cast}(#{reg} >> #{self.class.bits * i})")
        end
      end
    end
  end
end
