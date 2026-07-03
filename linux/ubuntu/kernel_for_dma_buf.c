 // gemm_dma_buf_large_weight400m.c
     2  // Large coherent DMA buffers for KV260 FPGA GEMM.
     3  // UAPI:
     4  //   ioctl nr 1: old compatible {a_phys,b_phys,c_phys,uint32_t size}
     5  //   ioctl nr 2: extended {a_phys,b_phys,c_phys,a_size,b_size,c_size}
     6  // mmap offsets:
     7  //   offset 0*PAGE -> A/feature buffer
     8  //   offset 1*PAGE -> B/weight  buffer
     9  //   offset 2*PAGE -> C/result  buffer
    10  //
    11  // Build on KV260:
    12  //   make -C /lib/modules/$(uname -r)/build M=$PWD modules
    13  // Load:
    14  //   sudo rmmod gemm_dma_buf 2>/dev/null
    15  //   sudo insmod gemm_dma_buf_large_weight400m.ko
    16
    17  #include <linux/device.h>
    18  #include <linux/dma-mapping.h>
    19  #include <linux/fs.h>
    20  #include <linux/init.h>
    21  #include <linux/ioctl.h>
    22  #include <linux/kernel.h>
    23  #include <linux/miscdevice.h>
    24  #include <linux/mm.h>
    25  #include <linux/module.h>
    26  #include <linux/slab.h>
    27  #include <linux/uaccess.h>
    28
    29  #define DRV_NAME "gemm_dma_buf"
    30
    31  // Stable K=896-only build. Keep A/C moderate and make B the persistent weight bank.
    32  // A/C only need to hold one feature/result tile; B stores packed weights once.
    33  #ifndef GEMM_A_BUF_SIZE
    34  #define GEMM_A_BUF_SIZE (64UL * 1024UL * 1024UL)
    35  #endif
    36  #ifndef GEMM_B_BUF_SIZE
    37  #define GEMM_B_BUF_SIZE (400UL * 1024UL * 1024UL)
    38  #endif
    39  #ifndef GEMM_C_BUF_SIZE
    40  #define GEMM_C_BUF_SIZE (64UL * 1024UL * 1024UL)
    41  #endif
    42
    43  #define GEMM_BUF_IOCTL_MAGIC 'G'
    44
    45  struct gemm_dma_buf_info_old {
    46      u64 a_phys;
    47      u64 b_phys;
    48      u64 c_phys;
    49      u32 size;
    50  };
    51
    52  struct gemm_dma_buf_info_ex {
    53      u64 a_phys;
    54      u64 b_phys;
    55      u64 c_phys;
    56      u64 a_size;
    57      u64 b_size;
    58      u64 c_size;
    59  };
    60
    61  #define GEMM_DMA_BUF_IOCTL_GET_INFO_OLD _IOR(GEMM_BUF_IOCTL_MAGIC, 1, struct gemm_dma_buf_info_old)
    62  #define GEMM_DMA_BUF_IOCTL_GET_INFO_EX  _IOR(GEMM_BUF_IOCTL_MAGIC, 2, struct gemm_dma_buf_info_ex)
    63
    64  struct gemm_dma_region {
    65      void *vaddr;
    66      dma_addr_t phys;
    67      size_t size;
    68  };
    69
    70  static struct gemm_dma_region g_a;
    71  static struct gemm_dma_region g_b;
    72  static struct gemm_dma_region g_c;
    73  static struct device *g_dev;
    74  static u64 g_dma_mask = DMA_BIT_MASK(32);
    75
    76  static int gemm_open(struct inode *inode, struct file *file)
    77  {
    78      return 0;
    79  }
    80
    81  static int gemm_release(struct inode *inode, struct file *file)
    82  {
    83      return 0;
    84  }
    85
    86  static long gemm_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
    87  {
    88      switch (cmd) {
    89      case GEMM_DMA_BUF_IOCTL_GET_INFO_OLD: {
    90          struct gemm_dma_buf_info_old info;
    91          memset(&info, 0, sizeof(info));
    92          info.a_phys = (u64)g_a.phys;
    93          info.b_phys = (u64)g_b.phys;
    94          info.c_phys = (u64)g_c.phys;
    95          // Old userspace assumes same size for all three buffers. Return the
    96          // smallest to avoid exposing an out-of-range length.
    97          info.size = (u32)min(g_a.size, min(g_b.size, g_c.size));
    98          if (copy_to_user((void __user *)arg, &info, sizeof(info)))
    99              return -EFAULT;
   100          return 0;
   101      }
   102      case GEMM_DMA_BUF_IOCTL_GET_INFO_EX: {
   103          struct gemm_dma_buf_info_ex info;
   104          memset(&info, 0, sizeof(info));
   105          info.a_phys = (u64)g_a.phys;
   106          info.b_phys = (u64)g_b.phys;
   107          info.c_phys = (u64)g_c.phys;
   108          info.a_size = (u64)g_a.size;
   109          info.b_size = (u64)g_b.size;
   110          info.c_size = (u64)g_c.size;
   111          if (copy_to_user((void __user *)arg, &info, sizeof(info)))
   112              return -EFAULT;
   113          return 0;
   114      }
   115      default:
   116          return -ENOTTY;
   117      }
   118  }
   119
   120  static int gemm_mmap(struct file *file, struct vm_area_struct *vma)
   121  {
   122      struct device *dev = g_dev;
   123      struct gemm_dma_region *r = NULL;
   124      unsigned long req_size = vma->vm_end - vma->vm_start;
   125      unsigned long selector = vma->vm_pgoff;
   126
   127      // Keep the old user ABI: offset 0/4096/8192 selects A/B/C.
   128      if (selector == 0) {
   129          r = &g_a;
   130      } else if (selector == 1) {
   131          r = &g_b;
   132      } else if (selector == 2) {
   133          r = &g_c;
   134      } else {
   135          pr_err(DRV_NAME ": mmap bad selector pgoff=%lu\n", selector);
   136          return -EINVAL;
   137      }
   138
   139      if (req_size > r->size) {
   140          pr_err(DRV_NAME ": mmap too large selector=%lu req=%lu limit=%zu\n", selector, req_size, r->size);
   141          return -EINVAL;
   142      }
   143
   144      vma->vm_pgoff = 0;
   145      return dma_mmap_coherent(dev, vma, r->vaddr, r->phys, req_size);
   146  }
   147
   148  static const struct file_operations gemm_fops = {
   149      .owner = THIS_MODULE,
   150      .open = gemm_open,
   151      .release = gemm_release,
   152      .unlocked_ioctl = gemm_ioctl,
   153      .mmap = gemm_mmap,
   154  };
   155
   156  static struct miscdevice gemm_miscdev = {
   157      .minor = MISC_DYNAMIC_MINOR,
   158      .name = "gemm_dma_buf",
   159      .fops = &gemm_fops,
   160  };
   161
   162  static int alloc_region(struct device *dev, struct gemm_dma_region *r, size_t size, const char *name)
   163  {
   164      r->size = size;
   165      r->vaddr = dma_alloc_coherent(dev, r->size, &r->phys, GFP_KERNEL);
   166      if (!r->vaddr) {
   167          pr_err(DRV_NAME ": dma_alloc_coherent %s failed size=%zu\n", name, r->size);
   168          r->size = 0;
   169          r->phys = 0;
   170          return -ENOMEM;
   171      }
   172
   173      memset(r->vaddr, 0, r->size);
   174      pr_info(DRV_NAME ": %s vaddr=%p phys=%pad size=%zu\n", name, r->vaddr, &r->phys, r->size);
   175      return 0;
   176  }
   177
   178  static void free_region(struct device *dev, struct gemm_dma_region *r, const char *name)
   179  {
   180      if (r->vaddr) {
   181          pr_info(DRV_NAME ": free %s phys=%pad size=%zu\n", name, &r->phys, r->size);
   182          dma_free_coherent(dev, r->size, r->vaddr, r->phys);
   183          r->vaddr = NULL;
   184          r->phys = 0;
   185          r->size = 0;
   186      }
   187  }
   188
   189  static int __init gemm_init(void)
   190  {
   191      int ret;
   192      struct device *dev;
   193
   194      ret = misc_register(&gemm_miscdev);
   195      if (ret) {
   196          pr_err(DRV_NAME ": misc_register failed ret=%d\n", ret);
   197          return ret;
   198      }
   199
   200      dev = gemm_miscdev.this_device;
   201      g_dev = dev;
   202
   203      /*
   204       * miscdevice is not a real platform DMA device, so dma_set_mask_and_coherent()
   205       * may fail with -EIO on KV260. Use the same style as the old PASS driver:
   206       * provide a dma_mask pointer and set the coherent mask.
   207       */
   208      dev->dma_mask = &g_dma_mask;
   209      dev->coherent_dma_mask = DMA_BIT_MASK(32);
   210
   211      ret = dma_set_coherent_mask(dev, DMA_BIT_MASK(32));
   212      if (ret) {
   213          pr_warn(DRV_NAME ": dma_set_coherent_mask returned %d, continue anyway\n", ret);
   214      }
   215
   216      ret = alloc_region(dev, &g_a, GEMM_A_BUF_SIZE, "A/feature");
   217      if (ret)
   218          goto fail;
   219      ret = alloc_region(dev, &g_b, GEMM_B_BUF_SIZE, "B/weight");
   220      if (ret)
   221          goto fail;
   222      ret = alloc_region(dev, &g_c, GEMM_C_BUF_SIZE, "C/result");
   223      if (ret)
   224          goto fail;
   225
   226      pr_info(DRV_NAME ": loaded OK A=%zu B=%zu C=%zu\n", g_a.size, g_b.size, g_c.size);
   227      return 0;
   228
   229  fail:
   230      free_region(dev, &g_c, "C/result");
   231      free_region(dev, &g_b, "B/weight");
   232      free_region(dev, &g_a, "A/feature");
   233      misc_deregister(&gemm_miscdev);
   234      return ret;
   235  }
   236
   237  static void __exit gemm_exit(void)
   238  {
   239      struct device *dev = g_dev;
   240      free_region(dev, &g_c, "C/result");
   241      free_region(dev, &g_b, "B/weight");
   242      free_region(dev, &g_a, "A/feature");
   243      misc_deregister(&gemm_miscdev);
   244      g_dev = NULL;
   245      pr_info(DRV_NAME ": unloaded\n");
   246  }
   247
   248  module_init(gemm_init);
   249  module_exit(gemm_exit);
   250
   251  MODULE_LICENSE("GPL");
   252  MODULE_AUTHOR("OpenAI ChatGPT / project integration");
   253  MODULE_DESCRIPTION("KV260 FPGA GEMM large coherent DMA buffers");
